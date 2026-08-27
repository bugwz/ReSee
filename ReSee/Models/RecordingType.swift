import Foundation

enum RecordingType: String, CaseIterable, Codable, Hashable, Identifiable {
    case stationary
    case fixedPointTour
    case spatialModel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stationary: "定点全景"
        case .fixedPointTour: "多点全景"
        case .spatialModel: "自由空间"
        }
    }

    var subtitle: String {
        switch self {
        case .stationary: "站在一个位置记录完整球面，生成可自由环视的 360° 全景"
        case .fixedPointTour: "记录三个固定点，每个点都可 360° 自由环视"
        case .spatialModel: "连续移动的高精度 6DoF 空间模型"
        }
    }

    var systemImage: String {
        switch self {
        case .stationary: "pano"
        case .fixedPointTour: "point.3.connected.trianglepath.dotted"
        case .spatialModel: "cube.transparent"
        }
    }

    var isAvailable: Bool { self != .spatialModel }

    var requiredViewpointCount: Int {
        switch self {
        case .stationary: 1
        case .fixedPointTour: 3
        case .spatialModel: 0
        }
    }

    var estimatedTime: String {
        switch self {
        case .stationary: "约 2 分钟"
        case .fixedPointTour: "约 6 分钟"
        case .spatialModel: "即将推出"
        }
    }
}

struct CaptureDirection: Identifiable, Hashable {
    let id: Int
    let bandIndex: Int
    let indexInBand: Int
    let yawRadians: Float
    let pitchRadians: Float

    var yawDegrees: Float { yawRadians * 180 / .pi }
    var pitchDegrees: Float { pitchRadians * 180 / .pi }

    static let all: [CaptureDirection] = {
        let bands: [(pitch: Float, count: Int)] = [
            (-75, 8), (-38, 12), (0, 12), (38, 12), (75, 8)
        ]
        var result: [CaptureDirection] = []
        for (bandIndex, band) in bands.enumerated() {
            for index in 0..<band.count {
                result.append(
                    CaptureDirection(
                        id: result.count,
                        bandIndex: bandIndex,
                        indexInBand: index,
                        yawRadians: Float(index) * 2 * .pi / Float(band.count),
                        pitchRadians: band.pitch * .pi / 180
                    )
                )
            }
        }
        return result
    }()

    static let bands: [[CaptureDirection]] = (0..<5).map { bandIndex in
        all.filter { $0.bandIndex == bandIndex }
    }

    /// A deterministic, row-by-row route that starts straight ahead and keeps
    /// each successive target close to the previous one within a latitude band.
    static let captureSequence: [CaptureDirection] = {
        let orderedIDs = Array(20...31)
            + Array((32...43).reversed())
            + Array(44...51)
            + Array((8...19).reversed())
            + Array(0...7)
        return orderedIDs.compactMap { id in
            all.first { $0.id == id }
        }
    }()

    static func nextUncaptured(in capturedDirectionIDs: Set<Int>) -> CaptureDirection? {
        captureSequence.first { !capturedDirectionIDs.contains($0.id) }
    }

    static func nearest(yawRadians: Float, pitchRadians: Float) -> CaptureDirection {
        let observed = unitVector(yaw: yawRadians, pitch: pitchRadians)
        return all.max { lhs, rhs in
            dot(unitVector(yaw: lhs.yawRadians, pitch: lhs.pitchRadians), observed)
                < dot(unitVector(yaw: rhs.yawRadians, pitch: rhs.pitchRadians), observed)
        } ?? all[0]
    }

    static func angularDistance(
        fromYaw yaw: Float,
        pitch: Float,
        to direction: CaptureDirection
    ) -> Float {
        let lhs = unitVector(yaw: yaw, pitch: pitch)
        let rhs = unitVector(yaw: direction.yawRadians, pitch: direction.pitchRadians)
        return acos(min(max(dot(lhs, rhs), -1), 1))
    }

    private static func unitVector(yaw: Float, pitch: Float) -> Vector3 {
        let horizontal = cos(pitch)
        return Vector3(
            x: horizontal * sin(yaw),
            y: sin(pitch),
            z: horizontal * cos(yaw)
        )
    }

    private static func dot(_ lhs: Vector3, _ rhs: Vector3) -> Float {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }
}

enum CaptureMotionPhase: String, Codable, Hashable {
    case scanning
    case movingToNextPoint
    case complete
}

struct CaptureProgressState: Equatable {
    static let targetCount = CaptureDirection.all.count
    static let maximumCaptureDrift: Float = 0.12

    var recordingType: RecordingType
    var trackingQuality: TrackingQuality = .unavailable
    var motionPhase: CaptureMotionPhase = .scanning
    var activeViewpointIndex = 0
    var capturedDirectionIDs: Set<Int> = []
    var completedViewpoints = 0
    var currentDirectionID: Int?
    var currentYawRadians: Float = 0
    var currentPitchRadians: Float = 0
    var activeViewpointHeadingRadians: Float = 0
    var currentPosition: Vector3 = .zero
    var viewpointPositions: [Vector3] = []
    var distanceFromActivePoint: Float = 0
    var meshAnchorCount = 0
    var supportsLiDAR = false
    var isStableForCapture = false
    var isPortraitCaptureOrientation = false

    var currentTargetDirection: CaptureDirection? {
        guard let currentDirectionID else { return nil }
        return CaptureDirection.all.first { $0.id == currentDirectionID }
    }

    var currentTargetYawRadians: Float? {
        currentTargetDirection.map {
            ($0.yawRadians + activeViewpointHeadingRadians).normalizedAngle
        }
    }

    var overallCoverage: Double {
        let completed = completedViewpoints * Self.targetCount
        let current = motionPhase == .scanning ? capturedDirectionIDs.count : 0
        let total = max(recordingType.requiredViewpointCount * Self.targetCount, 1)
        return min(Double(completed + current) / Double(total), 1)
    }

    var missingDirectionCount: Int {
        max(Self.targetCount - capturedDirectionIDs.count, 0)
    }

    var pointTitle: String {
        "点位 \(min(activeViewpointIndex + 1, recordingType.requiredViewpointCount))/\(recordingType.requiredViewpointCount)"
    }

    var guidance: String {
        if trackingQuality == .unavailable {
            return "缓慢移动手机，等待空间定位"
        }
        if trackingQuality == .limited {
            return "对准有纹理的物体，避免快速晃动"
        }
        if !isPortraitCaptureOrientation {
            return "请竖直握持手机，不要横向拍摄"
        }

        switch motionPhase {
        case .scanning where distanceFromActivePoint > Self.maximumCaptureDrift:
            return "请把手机移回原点，以手机为轴转动"
        case .scanning where !isStableForCapture:
            return "对准后停稳手机，正在消除手持抖动"
        case .scanning where missingDirectionCount == 0:
            return "球面记录完整，正在准备生成"
        case .scanning:
            guard let target = currentTargetDirection else { return "保持手机平稳" }
            let pitchDelta = target.pitchRadians - currentPitchRadians
            if pitchDelta > 0.24 {
                return "抬高手机，对准高亮缺口"
            }
            if pitchDelta < -0.24 {
                return "放低手机，对准高亮缺口"
            }
            return "缓慢转身，对准高亮缺口"
        case .movingToNextPoint:
            return "向前移动，距离当前点位至少 1 米"
        case .complete:
            return "记录完整，正在准备生成"
        }
    }
}

struct CaptureProgressTracker {
    struct Update: Equatable {
        var state: CaptureProgressState
        var capturedDirection: CaptureDirection?
        var didComplete: Bool
    }

    private(set) var state: CaptureProgressState
    private var activePointOrigin: Vector3?
    private var capturedByViewpoint: [Set<Int>]

    init(recordingType: RecordingType, supportsLiDAR: Bool = false) {
        state = CaptureProgressState(
            recordingType: recordingType,
            supportsLiDAR: supportsLiDAR
        )
        capturedByViewpoint = Array(
            repeating: [],
            count: max(recordingType.requiredViewpointCount, 1)
        )
    }

    mutating func update(
        position: Vector3,
        yawRadians: Float,
        pitchRadians: Float,
        trackingQuality: TrackingQuality,
        meshAnchorCount: Int,
        isStableForCapture: Bool = true,
        isPortraitCaptureOrientation: Bool = true,
        captureFrame: Bool = true
    ) -> Update {
        state.trackingQuality = trackingQuality
        state.currentPosition = position
        state.currentYawRadians = yawRadians.normalizedAngle
        state.currentPitchRadians = pitchRadians
        state.meshAnchorCount = meshAnchorCount
        state.isStableForCapture = isStableForCapture
        state.isPortraitCaptureOrientation = isPortraitCaptureOrientation

        if activePointOrigin == nil, trackingQuality == .normal {
            activePointOrigin = position
            state.viewpointPositions = [position]
            state.activeViewpointHeadingRadians = state.currentYawRadians
        }
        if let activePointOrigin {
            state.distanceFromActivePoint = position.distance(to: activePointOrigin)
        }

        guard trackingQuality == .normal, state.motionPhase != .complete else {
            return Update(state: state, didComplete: state.motionPhase == .complete)
        }

        if state.motionPhase == .movingToNextPoint {
            guard state.distanceFromActivePoint >= 1 else {
                return Update(state: state, didComplete: false)
            }
            activePointOrigin = position
            state.viewpointPositions.append(position)
            state.activeViewpointHeadingRadians = state.currentYawRadians
            state.distanceFromActivePoint = 0
            state.motionPhase = .scanning
            state.capturedDirectionIDs = capturedByViewpoint[state.activeViewpointIndex]
        }

        let relativeYaw = (
            state.currentYawRadians - state.activeViewpointHeadingRadians
        ).normalizedAngle
        guard let target = CaptureDirection.nextUncaptured(
            in: capturedByViewpoint[state.activeViewpointIndex]
        ) else {
            return Update(state: state, didComplete: false)
        }
        state.currentDirectionID = target.id

        guard state.distanceFromActivePoint <= CaptureProgressState.maximumCaptureDrift,
              state.isStableForCapture,
              state.isPortraitCaptureOrientation,
              CaptureDirection.angularDistance(
                fromYaw: relativeYaw,
                pitch: pitchRadians,
                to: target
              ) <= 14 * .pi / 180,
              captureFrame else {
            return Update(state: state, didComplete: false)
        }

        let inserted = capturedByViewpoint[state.activeViewpointIndex].insert(target.id).inserted
        state.capturedDirectionIDs = capturedByViewpoint[state.activeViewpointIndex]

        guard state.capturedDirectionIDs.count == CaptureProgressState.targetCount else {
            state.currentDirectionID = CaptureDirection.nextUncaptured(
                in: state.capturedDirectionIDs
            )?.id
            return Update(
                state: state,
                capturedDirection: inserted ? target : nil,
                didComplete: false
            )
        }

        state.completedViewpoints = state.activeViewpointIndex + 1
        if state.completedViewpoints >= state.recordingType.requiredViewpointCount {
            state.motionPhase = .complete
            return Update(
                state: state,
                capturedDirection: inserted ? target : nil,
                didComplete: true
            )
        }

        state.activeViewpointIndex += 1
        state.motionPhase = .movingToNextPoint
        state.capturedDirectionIDs = []
        state.currentDirectionID = nil
        return Update(
            state: state,
            capturedDirection: inserted ? target : nil,
            didComplete: false
        )
    }
}

struct CaptureMotionStabilityTracker {
    struct Result: Equatable {
        var linearSpeed: Float
        var angularSpeed: Float
        var stableDuration: TimeInterval
        var isReady: Bool
    }

    static let maximumLinearSpeed: Float = 0.06
    static let maximumAngularSpeed: Float = 5 * .pi / 180
    static let requiredStableDuration: TimeInterval = 0.28

    private var previousTimestamp: TimeInterval?
    private var previousPosition: Vector3?
    private var previousForward: Vector3?
    private var previousUp: Vector3?
    private var stableSince: TimeInterval?
    private var smoothedLinearSpeed: Float = 0
    private var smoothedAngularSpeed: Float = 0

    mutating func update(
        timestamp: TimeInterval,
        position: Vector3,
        forward: Vector3,
        up: Vector3 = Vector3(x: 0, y: 1, z: 0)
    ) -> Result {
        defer {
            previousTimestamp = timestamp
            previousPosition = position
            previousForward = forward
            previousUp = up
        }
        guard let previousTimestamp,
              let previousPosition,
              let previousForward,
              let previousUp else {
            stableSince = nil
            return Result(
                linearSpeed: 0,
                angularSpeed: 0,
                stableDuration: 0,
                isReady: false
            )
        }

        let elapsed = timestamp - previousTimestamp
        guard elapsed > 0, elapsed < 0.25 else {
            stableSince = nil
            smoothedLinearSpeed = 0
            smoothedAngularSpeed = 0
            return Result(
                linearSpeed: 0,
                angularSpeed: 0,
                stableDuration: 0,
                isReady: false
            )
        }

        let linearSpeed = position.distance(to: previousPosition) / Float(elapsed)
        func angleBetween(_ lhs: Vector3, _ rhs: Vector3) -> Float {
            let value = lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
            return acos(min(max(value, -1), 1))
        }
        let angularSpeed = max(
            angleBetween(forward, previousForward),
            angleBetween(up, previousUp)
        ) / Float(elapsed)
        let smoothing: Float = 0.28
        smoothedLinearSpeed += (linearSpeed - smoothedLinearSpeed) * smoothing
        smoothedAngularSpeed += (angularSpeed - smoothedAngularSpeed) * smoothing

        let isInstantlyStable = smoothedLinearSpeed <= Self.maximumLinearSpeed
            && smoothedAngularSpeed <= Self.maximumAngularSpeed
        if isInstantlyStable {
            stableSince = stableSince ?? timestamp
        } else {
            stableSince = nil
        }
        let stableDuration = stableSince.map { timestamp - $0 } ?? 0
        return Result(
            linearSpeed: smoothedLinearSpeed,
            angularSpeed: smoothedAngularSpeed,
            stableDuration: stableDuration,
            isReady: stableDuration >= Self.requiredStableDuration
        )
    }

    mutating func reset() {
        self = CaptureMotionStabilityTracker()
    }
}

extension Float {
    var normalizedAngle: Float {
        let circle = 2 * Float.pi
        let value = truncatingRemainder(dividingBy: circle)
        return value >= 0 ? value : value + circle
    }

    var shortestSignedAngle: Float {
        let normalized = normalizedAngle
        return normalized > .pi ? normalized - 2 * .pi : normalized
    }
}

extension Vector3 {
    func distance(to other: Vector3) -> Float {
        let dx = x - other.x
        let dy = y - other.y
        let dz = z - other.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
}
