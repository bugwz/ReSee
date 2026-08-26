import CoreImage
import Foundation
import Metal
import MetalKit

enum SceneRenderingError: LocalizedError {
    case insufficientFrames(expected: Int, actual: Int)
    case invalidFrameData
    case invalidCalibration
    case metalUnavailable
    case shaderUnavailable
    case panoramaCreationFailed
    case outputAlreadyExists

    var errorDescription: String? {
        switch self {
        case let .insufficientFrames(expected, actual):
            "球面采集数据不完整：需要 \(expected) 帧，实际收到 \(actual) 帧。"
        case .invalidFrameData:
            "采集图片无法读取，请重新记录。"
        case .invalidCalibration:
            "相机标定数据不完整，无法生成全景。"
        case .metalUnavailable:
            "当前设备无法使用全景生成所需的图形处理能力。"
        case .shaderUnavailable:
            "全景生成组件未正确载入。"
        case .panoramaCreationFailed:
            "360° 全景图片写入失败。"
        case .outputAlreadyExists:
            "该场景已经生成，请返回资料库查看。"
        }
    }
}

actor SceneRenderingService {
    typealias ProgressHandler = @MainActor @Sendable (Double, String) -> Void

    private struct ProjectionParameters {
        var worldToCameraRow0: SIMD4<Float>
        var worldToCameraRow1: SIMD4<Float>
        var worldToCameraRow2: SIMD4<Float>
        var intrinsics: SIMD4<Float>
        var sourceSize: SIMD2<UInt32>
        var verticalDirectionSign: Float
        var padding: Float = 0
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let panoramaWidth: Int

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        panoramaWidth: Int = 4096
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? SceneAssetStore.defaultRootURL(fileManager: fileManager)
        self.panoramaWidth = max(512, panoramaWidth + panoramaWidth % 2)
    }

    func render(
        sceneID: UUID,
        recordingType: RecordingType,
        frames: [CapturedFramePayload],
        progress: ProgressHandler
    ) async throws -> RenderedScene {
        let framesPerPoint = CaptureProgressState.targetCount
        let expectedCount = recordingType.requiredViewpointCount * framesPerPoint
        guard frames.count == expectedCount else {
            throw SceneRenderingError.insufficientFrames(
                expected: expectedCount,
                actual: frames.count
            )
        }

        await progress(0.05, "正在检查球面覆盖与相机位姿")
        let sceneURL = rootURL.appendingPathComponent(sceneID.uuidString, isDirectory: true)
        let renderedURL = sceneURL.appendingPathComponent("rendered", isDirectory: true)
        let stagingURL = sceneURL.appendingPathComponent(
            ".rendering-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingURL)
            if let contents = try? fileManager.contentsOfDirectory(
                at: sceneURL,
                includingPropertiesForKeys: nil
            ), contents.isEmpty {
                try? fileManager.removeItem(at: sceneURL)
            }
        }

        let grouped = Dictionary(grouping: frames, by: \.viewpointIndex)
        var viewpoints: [RenderedViewpoint] = []

        for viewpointIndex in 0..<recordingType.requiredViewpointCount {
            let pointFrames = (grouped[viewpointIndex] ?? [])
                .sorted { $0.directionID < $1.directionID }
            let uniqueDirections = Set(pointFrames.map(\.directionID))
            guard pointFrames.count == framesPerPoint,
                  uniqueDirections == Set(CaptureDirection.all.map(\.id)) else {
                throw SceneRenderingError.insufficientFrames(
                    expected: framesPerPoint,
                    actual: uniqueDirections.count
                )
            }

            let pointURL = stagingURL.appendingPathComponent(
                String(format: "viewpoint-%02d", viewpointIndex),
                isDirectory: true
            )
            try fileManager.createDirectory(at: pointURL, withIntermediateDirectories: true)
            let panoramaURL = pointURL.appendingPathComponent("panorama.jpg")

            await progress(
                0.08 + Double(viewpointIndex * framesPerPoint) / Double(expectedCount) * 0.82,
                "正在合成点位 \(viewpointIndex + 1) 的 360° 全景"
            )
            try composePanorama(
                frames: pointFrames,
                outputURL: panoramaURL
            )
            await progress(
                0.08 + Double((viewpointIndex + 1) * framesPerPoint) / Double(expectedCount) * 0.82,
                "点位 \(viewpointIndex + 1) 全景已生成"
            )

            viewpoints.append(
                RenderedViewpoint(
                    id: UUID(),
                    index: viewpointIndex,
                    name: "点位 \(viewpointIndex + 1)",
                    position: pointFrames.first?.position ?? .zero,
                    panoramaPath: "rendered/\(pointURL.lastPathComponent)/panorama.jpg",
                    sourceFrameCount: pointFrames.count
                )
            )
        }

        let result = RenderedScene(
            generationState: .ready,
            generatedAt: .now,
            viewpoints: viewpoints,
            thumbnailPath: viewpoints.first?.panoramaPath
        )
        let metadataURL = stagingURL.appendingPathComponent("scene.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result).write(to: metadataURL, options: .atomic)

        guard !fileManager.fileExists(atPath: renderedURL.path) else {
            throw SceneRenderingError.outputAlreadyExists
        }
        try fileManager.moveItem(at: stagingURL, to: renderedURL)
        await progress(1, "360° 全景生成完成")
        return result
    }

    func discard(sceneID: UUID) throws {
        let sceneURL = rootURL.appendingPathComponent(sceneID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: sceneURL.path) else { return }
        try fileManager.removeItem(at: sceneURL)
    }

    private func composePanorama(
        frames: [CapturedFramePayload],
        outputURL: URL
    ) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw SceneRenderingError.metalUnavailable
        }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.metalSource, options: nil)
        } catch {
            throw SceneRenderingError.shaderUnavailable
        }
        guard let clearFunction = library.makeFunction(name: "clearBlendTargets"),
              let projectionFunction = library.makeFunction(name: "accumulateFrame"),
              let normalizationFunction = library.makeFunction(name: "normalizePanorama") else {
            throw SceneRenderingError.shaderUnavailable
        }

        let clearPipeline = try device.makeComputePipelineState(function: clearFunction)
        let projectionPipeline = try device.makeComputePipelineState(function: projectionFunction)
        let normalizationPipeline = try device.makeComputePipelineState(
            function: normalizationFunction
        )
        let panorama = try makeTexture(
            device: device,
            pixelFormat: .rgba8Unorm,
            width: panoramaWidth,
            height: panoramaWidth / 2
        )
        let accumulatedColor = try makeTexture(
            device: device,
            pixelFormat: .rgba16Float,
            width: panoramaWidth,
            height: panoramaWidth / 2
        )
        let accumulatedWeight = try makeTexture(
            device: device,
            pixelFormat: .r16Float,
            width: panoramaWidth,
            height: panoramaWidth / 2
        )
        try execute(
            commandQueue: commandQueue,
            pipeline: clearPipeline,
            textures: [accumulatedColor, accumulatedWeight],
            width: panorama.width,
            height: panorama.height
        )

        let textureLoader = MTKTextureLoader(device: device)
        let verticalDirectionSign = Self.detectVerticalDirectionSign(in: frames)
        for frame in frames {
            guard !frame.jpegData.isEmpty else {
                throw SceneRenderingError.invalidFrameData
            }
            let calibration = frame.calibration
            guard calibration.cameraTransform.count == 16,
                  calibration.intrinsics.count == 4,
                  calibration.imageWidth > 0,
                  calibration.imageHeight > 0 else {
                throw SceneRenderingError.invalidCalibration
            }

            let source: MTLTexture
            do {
                source = try textureLoader.newTexture(
                    data: frame.jpegData,
                    options: [
                        .SRGB: false,
                        .origin: MTKTextureLoader.Origin.topLeft
                    ]
                )
            } catch {
                throw SceneRenderingError.invalidFrameData
            }
            guard source.width == calibration.imageWidth,
                  source.height == calibration.imageHeight else {
                throw SceneRenderingError.invalidCalibration
            }

            let transform = calibration.cameraTransform
            var parameters = ProjectionParameters(
                worldToCameraRow0: SIMD4(transform[0], transform[1], transform[2], 0),
                worldToCameraRow1: SIMD4(transform[4], transform[5], transform[6], 0),
                worldToCameraRow2: SIMD4(transform[8], transform[9], transform[10], 0),
                intrinsics: SIMD4(
                    calibration.intrinsics[0],
                    calibration.intrinsics[1],
                    calibration.intrinsics[2],
                    calibration.intrinsics[3]
                ),
                sourceSize: SIMD2(UInt32(source.width), UInt32(source.height)),
                verticalDirectionSign: verticalDirectionSign
            )
            try execute(
                commandQueue: commandQueue,
                pipeline: projectionPipeline,
                textures: [source, accumulatedColor, accumulatedWeight],
                width: panorama.width,
                height: panorama.height,
                parameters: &parameters
            )
        }
        try execute(
            commandQueue: commandQueue,
            pipeline: normalizationPipeline,
            textures: [accumulatedColor, accumulatedWeight, panorama],
            width: panorama.width,
            height: panorama.height
        )

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let image = CIImage(
            mtlTexture: panorama,
            options: [.colorSpace: colorSpace]
        ) else {
            throw SceneRenderingError.panoramaCreationFailed
        }
        let sharpenedImage = image.applyingFilter(
            "CIUnsharpMask",
            parameters: [
                kCIInputRadiusKey: 1.2,
                kCIInputIntensityKey: 0.32
            ]
        )
        let context = CIContext(mtlDevice: device)
        do {
            try context.writeJPEGRepresentation(
                of: sharpenedImage,
                to: outputURL,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.94]
            )
        } catch {
            throw SceneRenderingError.panoramaCreationFailed
        }
    }

    private func makeTexture(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw SceneRenderingError.panoramaCreationFailed
        }
        return texture
    }

    nonisolated static func detectVerticalDirectionSign(
        in frames: [CapturedFramePayload]
    ) -> Float {
        let alignment = frames.reduce(Float.zero) { result, frame in
            guard frame.calibration.cameraTransform.count == 16 else { return result }
            let expectedVertical = sin(frame.pitchDegrees * .pi / 180)
            guard abs(expectedVertical) > 0.2 else { return result }
            let measuredVertical = -frame.calibration.cameraTransform[9]
            return result + expectedVertical * measuredVertical
        }
        return alignment < 0 ? -1 : 1
    }

    private func execute(
        commandQueue: MTLCommandQueue,
        pipeline: MTLComputePipelineState,
        textures: [MTLTexture],
        width: Int,
        height: Int,
        parameters: UnsafeMutableRawPointer? = nil
    ) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw SceneRenderingError.panoramaCreationFailed
        }
        encoder.setComputePipelineState(pipeline)
        for (index, texture) in textures.enumerated() {
            encoder.setTexture(texture, index: index)
        }
        if let parameters {
            encoder.setBytes(
                parameters,
                length: MemoryLayout<ProjectionParameters>.stride,
                index: 0
            )
        }
        let threads = MTLSize(
            width: pipeline.threadExecutionWidth,
            height: max(pipeline.maxTotalThreadsPerThreadgroup / pipeline.threadExecutionWidth, 1),
            depth: 1
        )
        encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: threads
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status == .error {
            throw commandBuffer.error ?? SceneRenderingError.panoramaCreationFailed
        }
    }

    private static let metalSource = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct PanoramaProjectionParameters {
        float4 worldToCameraRow0;
        float4 worldToCameraRow1;
        float4 worldToCameraRow2;
        float4 intrinsics;
        uint2 sourceSize;
        float verticalDirectionSign;
        float padding;
    };

    kernel void clearBlendTargets(
        texture2d<float, access::write> accumulatedColor [[texture(0)]],
        texture2d<float, access::write> accumulatedWeight [[texture(1)]],
        uint2 position [[thread_position_in_grid]]
    ) {
        if (position.x >= accumulatedColor.get_width()
            || position.y >= accumulatedColor.get_height()) {
            return;
        }
        accumulatedColor.write(float4(0.0), position);
        accumulatedWeight.write(float4(0.0), position);
    }

    kernel void accumulateFrame(
        texture2d<float, access::sample> source [[texture(0)]],
        texture2d<float, access::read_write> accumulatedColor [[texture(1)]],
        texture2d<float, access::read_write> accumulatedWeight [[texture(2)]],
        constant PanoramaProjectionParameters &parameters [[buffer(0)]],
        uint2 position [[thread_position_in_grid]]
    ) {
        const uint width = accumulatedColor.get_width();
        const uint height = accumulatedColor.get_height();
        if (position.x >= width || position.y >= height) {
            return;
        }

        const float longitude = ((float(position.x) + 0.5) / float(width))
            * 2.0 * M_PI_F - M_PI_F;
        const float latitude = (0.5 - (float(position.y) + 0.5) / float(height))
            * M_PI_F * parameters.verticalDirectionSign;
        const float horizontal = cos(latitude);
        const float3 worldDirection = float3(
            horizontal * sin(longitude),
            sin(latitude),
            horizontal * cos(longitude)
        );
        const float3 cameraDirection = float3(
            dot(parameters.worldToCameraRow0.xyz, worldDirection),
            dot(parameters.worldToCameraRow1.xyz, worldDirection),
            dot(parameters.worldToCameraRow2.xyz, worldDirection)
        );
        const float depth = -cameraDirection.z;
        if (depth <= 0.01) {
            return;
        }

        const float pixelX = parameters.intrinsics.x * cameraDirection.x / depth
            + parameters.intrinsics.z;
        const float pixelY = parameters.intrinsics.y * -cameraDirection.y / depth
            + parameters.intrinsics.w;
        if (pixelX < 1.0 || pixelY < 1.0
            || pixelX >= float(parameters.sourceSize.x - 1)
            || pixelY >= float(parameters.sourceSize.y - 1)) {
            return;
        }

        const float edgeDistance = min(
            min(pixelX, float(parameters.sourceSize.x - 1) - pixelX),
            min(pixelY, float(parameters.sourceSize.y - 1) - pixelY)
        );
        const float featherWidth = max(
            8.0,
            float(min(parameters.sourceSize.x, parameters.sourceSize.y)) * 0.24
        );
        const float edgeWeight = smoothstep(0.0, featherWidth, edgeDistance);
        const float axisWeight = pow(saturate(depth), 28.0);
        const float weight = edgeWeight * axisWeight;
        if (weight <= 0.0001) {
            return;
        }

        constexpr sampler imageSampler(
            coord::normalized,
            address::clamp_to_edge,
            filter::linear
        );
        const float2 sourceCoordinate = float2(
            (pixelX + 0.5) / float(parameters.sourceSize.x),
            (pixelY + 0.5) / float(parameters.sourceSize.y)
        );
        const float4 color = source.sample(imageSampler, sourceCoordinate);
        accumulatedColor.write(
            accumulatedColor.read(position) + color * weight,
            position
        );
        accumulatedWeight.write(
            accumulatedWeight.read(position) + float4(weight),
            position
        );
    }

    kernel void normalizePanorama(
        texture2d<float, access::read> accumulatedColor [[texture(0)]],
        texture2d<float, access::read> accumulatedWeight [[texture(1)]],
        texture2d<float, access::write> panorama [[texture(2)]],
        uint2 position [[thread_position_in_grid]]
    ) {
        if (position.x >= panorama.get_width() || position.y >= panorama.get_height()) {
            return;
        }
        const float weight = accumulatedWeight.read(position).r;
        if (weight <= 0.0001) {
            panorama.write(float4(0.0, 0.0, 0.0, 1.0), position);
            return;
        }
        const float3 color = accumulatedColor.read(position).rgb / weight;
        panorama.write(float4(color, 1.0), position);
    }
    """#
}

enum SceneAssetStore {
    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scenes", isDirectory: true)
    }

    static func url(sceneID: UUID, relativePath: String) -> URL {
        defaultRootURL()
            .appendingPathComponent(sceneID.uuidString, isDirectory: true)
            .appendingPathComponent(relativePath)
    }
}
