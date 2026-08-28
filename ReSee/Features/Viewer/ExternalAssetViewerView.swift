import SwiftUI

struct ExternalAssetViewerView: View {
    @EnvironmentObject private var repository: ExternalAssetRepository
    @EnvironmentObject private var settings: AppSettings
    let asset: ExternalAsset

    @State private var scopedAsset: ScopedExternalAsset?
    @State private var loadError: String?
    @State private var activeIndex = 0
    @State private var resetToken = 0
    @State private var isHorizontallyInverted = false
    @State private var isVerticallyInverted = false
    @State private var isPresentingLandscape = false
    @State private var hasAutoPresentedLandscape = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                viewer
                if asset.kind == .multiPointPanorama, let scopedAsset {
                    viewpointPicker(scopedAsset.resources)
                }
                informationSection
                fileSection
            }
            .padding(18)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: asset.id) { resolveAccess() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingLandscape = true
                } label: {
                    Label("横屏沉浸查看", systemImage: "rectangle.landscape.rotate")
                }
                .disabled(scopedAsset == nil)
            }
        }
        .fullScreenCover(isPresented: $isPresentingLandscape) {
            if let scopedAsset {
                ExternalAssetLandscapeView(
                    asset: asset,
                    scopedAsset: scopedAsset,
                    activeIndex: $activeIndex,
                    resetToken: $resetToken,
                    isHorizontallyInverted: $isHorizontallyInverted,
                    isVerticallyInverted: $isVerticallyInverted,
                    startsWithMotion: settings.isMotionViewingEnabled
                )
            }
        }
        .alert("文件不可用", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("知道了", role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "未知错误")
        }
    }

    @ViewBuilder
    private var viewer: some View {
        if let scopedAsset {
            switch asset.kind {
            case .stationaryPanorama, .multiPointPanorama:
                if scopedAsset.resources.indices.contains(activeIndex) {
                    panoramaViewer(url: scopedAsset.resources[activeIndex].url)
                }
            case .gaussianSplat:
                if let resource = scopedAsset.resources.first {
                    GaussianSplatViewerView(fileURL: resource.url)
                        .frame(height: 560)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        } else if loadError == nil {
            ProgressView("正在打开资源…")
                .frame(maxWidth: .infinity)
                .frame(height: 360)
        } else {
            ContentUnavailableView(
                "文件不可用",
                systemImage: "doc.badge.ellipsis",
                description: Text("原文件可能已被移动或删除，请重新载入或使用复制方式导入。")
            )
            .frame(height: 360)
        }
    }

    private func panoramaViewer(url: URL) -> some View {
        ZStack {
            PanoramaSceneView(
                imageURL: url,
                interactionMode: .touch,
                resetToken: resetToken,
                isHorizontallyInverted: isHorizontallyInverted,
                isVerticallyInverted: isVerticallyInverted
            )

            VStack {
                HStack {
                    Label("360°", systemImage: "view.360")
                    Spacer()
                    Text(asset.kind.title)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.4))
                Spacer()
                HStack {
                    panoramaButton("arrow.counterclockwise", label: "复位视角") {
                        resetToken += 1
                    }
                    Spacer()
                    panoramaButton("arrow.left.and.right", label: "左右翻转") {
                        isHorizontallyInverted.toggle()
                    }
                    panoramaButton("arrow.up.and.down", label: "上下翻转") {
                        isVerticallyInverted.toggle()
                    }
                }
                .padding(12)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .frame(maxHeight: 520)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func panoramaButton(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.52), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func viewpointPicker(_ resources: [ScopedExternalAsset.Resource]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("切换全景点位").font(.headline)
                Spacer()
                Text("\(activeIndex + 1)/\(resources.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(resources.enumerated()), id: \.element.file.id) { index, resource in
                        Button {
                            activeIndex = index
                            resetToken += 1
                        } label: {
                            VStack(spacing: 5) {
                                Text("\(index + 1)")
                                    .font(.headline.monospacedDigit())
                                Text(resource.file.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(index == activeIndex ? .white : .primary)
                            .padding(.horizontal, 14)
                            .frame(height: 58)
                            .background(
                                index == activeIndex ? AppTheme.accent : AppTheme.panel,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var informationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("资源信息").font(.headline)
            LabeledContent("类型", value: asset.kind.title)
            LabeledContent("来源", value: asset.storage.title)
            LabeledContent("格式", value: asset.formatSummary)
            LabeledContent("文件数量", value: "\(asset.files.count)")
            LabeledContent("总大小", value: asset.totalByteCount.formattedFileSize)
            if let sourceURL = asset.sourceURL {
                LabeledContent("下载地址") {
                    Text(sourceURL).lineLimit(1).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("数据文件").font(.headline)
            ForEach(asset.files) { file in
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.displayName).font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        Text(file.byteCount.formattedFileSize)
                        if let dimensions = file.dimensionsText { Text(dimensions) }
                        Text(file.relativePath == nil ? "外部引用" : "应用内文件")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if file.id != asset.files.last?.id { Divider() }
            }
        }
        .padding(16)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private func resolveAccess() {
        do {
            scopedAsset = try repository.scopedAccess(to: asset)
            activeIndex = min(activeIndex, max(asset.files.count - 1, 0))
            if !hasAutoPresentedLandscape {
                hasAutoPresentedLandscape = true
                isPresentingLandscape = true
            }
        } catch {
            scopedAsset = nil
            loadError = error.localizedDescription
        }
    }
}

private struct ExternalAssetLandscapeView: View {
    @Environment(\.dismiss) private var dismiss

    let asset: ExternalAsset
    let scopedAsset: ScopedExternalAsset
    @Binding var activeIndex: Int
    @Binding var resetToken: Int
    @Binding var isHorizontallyInverted: Bool
    @Binding var isVerticallyInverted: Bool

    @State private var interactionMode: PanoramaInteractionMode
    @State private var isMotionAvailable = true

    init(
        asset: ExternalAsset,
        scopedAsset: ScopedExternalAsset,
        activeIndex: Binding<Int>,
        resetToken: Binding<Int>,
        isHorizontallyInverted: Binding<Bool>,
        isVerticallyInverted: Binding<Bool>,
        startsWithMotion: Bool
    ) {
        self.asset = asset
        self.scopedAsset = scopedAsset
        _activeIndex = activeIndex
        _resetToken = resetToken
        _isHorizontallyInverted = isHorizontallyInverted
        _isVerticallyInverted = isVerticallyInverted
        _interactionMode = State(initialValue: startsWithMotion ? .motion : .touch)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            landscapeContent
            topBar
            if asset.kind == .multiPointPanorama {
                landscapeViewpointPicker
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { AppOrientationController.request(.landscape) }
        .onDisappear { AppOrientationController.request(.portrait) }
    }

    @ViewBuilder
    private var landscapeContent: some View {
        switch asset.kind {
        case .stationaryPanorama, .multiPointPanorama:
            if scopedAsset.resources.indices.contains(activeIndex) {
                PanoramaSceneView(
                    imageURL: scopedAsset.resources[activeIndex].url,
                    interactionMode: interactionMode,
                    resetToken: resetToken,
                    isHorizontallyInverted: isHorizontallyInverted,
                    isVerticallyInverted: isVerticallyInverted,
                    onMotionAvailabilityChanged: { available in
                        isMotionAvailable = available
                        if !available { interactionMode = .touch }
                    }
                )
                .ignoresSafeArea()
            }
        case .gaussianSplat:
            if let resource = scopedAsset.resources.first {
                GaussianSplatViewerView(fileURL: resource.url)
                    .ignoresSafeArea()
            }
        }
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                landscapeButton("xmark", label: "退出沉浸查看") { dismiss() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name).font(.subheadline.weight(.semibold))
                    Text(asset.kind.title).font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                .foregroundStyle(.white)
                Spacer()
                if asset.kind != .gaussianSplat {
                    modeControl
                    landscapeButton("arrow.left.and.right", label: "左右翻转") {
                        isHorizontallyInverted.toggle()
                    }
                    landscapeButton("arrow.up.and.down", label: "上下翻转") {
                        isVerticallyInverted.toggle()
                    }
                    landscapeButton("arrow.counterclockwise", label: "复位视角") {
                        resetToken += 1
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.48))
            Spacer()
        }
    }

    private var modeControl: some View {
        HStack(spacing: 2) {
            modeButton(.touch, title: "触摸", image: "hand.draw")
            modeButton(.motion, title: "跟随", image: "gyroscope")
                .disabled(!isMotionAvailable)
                .opacity(isMotionAvailable ? 1 : 0.42)
        }
        .padding(3)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
    }

    private func modeButton(
        _ mode: PanoramaInteractionMode,
        title: String,
        image: String
    ) -> some View {
        Button {
            interactionMode = mode
        } label: {
            Label(title, systemImage: image)
                .font(.caption.weight(.semibold))
                .foregroundStyle(interactionMode == mode ? .black : .white)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    interactionMode == mode ? Color.white : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
    }

    private var landscapeViewpointPicker: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                ForEach(Array(scopedAsset.resources.enumerated()), id: \.element.file.id) { index, _ in
                    Button {
                        activeIndex = index
                        resetToken += 1
                    } label: {
                        Text("点位 \(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(
                                index == activeIndex ? AppTheme.accent : Color.black.opacity(0.52),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 14)
        }
    }

    private func landscapeButton(
        _ image: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
