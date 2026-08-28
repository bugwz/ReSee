import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var repository: SceneRepository
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            syncSection
            captureSection
            viewingSection
            generalSection
            privacySection
            aboutSection
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
    }

    private var syncSection: some View {
        Section {
            Toggle(isOn: $settings.isICloudSyncEnabled) {
                Label("iCloud 数据同步", systemImage: "icloud")
            }
            .onChange(of: settings.isICloudSyncEnabled) { _, enabled in
                Task { await repository.configureICloudSync(enabled: enabled) }
            }

            if settings.isICloudSyncEnabled {
                LabeledContent("同步状态") {
                    HStack(spacing: 7) {
                        if repository.iCloudSyncState == .syncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Circle()
                                .fill(syncStatusColor)
                                .frame(width: 7, height: 7)
                        }
                        Text(repository.iCloudSyncState.title)
                            .foregroundStyle(.secondary)
                    }
                }

                if let detail = repository.iCloudSyncState.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await repository.synchronizeWithICloud() }
                } label: {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(repository.iCloudSyncState == .syncing)

                if let date = repository.lastICloudSyncAt {
                    LabeledContent("最近同步") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("数据与 iCloud")
        } footer: {
            Text("开启后，场景索引和已生成的全景文件会同步到 iCloud Drive/回见/Scenes。当前不上传原始相机帧、深度或网格。")
        }
    }

    private var captureSection: some View {
        Section("记录与生成") {
            NavigationLink {
                PanoramaOutputSettingsView()
            } label: {
                SettingsSummaryRow(
                    icon: "photo.badge.gearshape",
                    title: "全景文件",
                    detail: "\(settings.panoramaFormat.title) · \(settings.panoramaResolution.title)"
                )
            }

            Toggle(isOn: $settings.isCaptureHapticsEnabled) {
                Label("采集完成触感", systemImage: "iphone.radiowaves.left.and.right")
            }

            Toggle(isOn: $settings.keepsScreenAwakeDuringCapture) {
                Label("记录时保持屏幕常亮", systemImage: "sun.max")
            }
        }
    }

    private var viewingSection: some View {
        Section {
            Toggle(isOn: $settings.isMotionViewingEnabled) {
                Label("横屏时默认跟随手机", systemImage: "gyroscope")
            }
        } header: {
            Text("浏览")
        } footer: {
            Text("开启后，进入横屏沉浸浏览会优先使用设备姿态环视，仍可随时切换为触摸。")
        }
    }

    private var generalSection: some View {
        Section {
            Picker(selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            } label: {
                Label("语言", systemImage: "character.bubble")
            }

            Picker(selection: $settings.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            } label: {
                Label("外观", systemImage: "circle.lefthalf.filled")
            }
        } header: {
            Text("通用")
        } footer: {
            Text("当前版本提供简体中文内容；选择“跟随系统”会为后续语言包沿用系统语言偏好。")
        }
    }

    private var privacySection: some View {
        Section("隐私与存储") {
            LabeledContent {
                Text("\(repository.scenes.count) 个")
                    .foregroundStyle(.secondary)
            } label: {
                Label("本地场景", systemImage: "internaldrive")
            }

            NavigationLink {
                DataAndPrivacyView()
            } label: {
                Label("数据说明", systemImage: "hand.raised")
            }
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                SettingsAboutView()
            } label: {
                Label("关于回见", systemImage: "info.circle")
            }

            LabeledContent("版本") {
                Text(versionText).foregroundStyle(.secondary)
            }
        }
    }

    private var syncStatusColor: Color {
        switch repository.iCloudSyncState {
        case .idle: AppTheme.success
        case .disabled, .syncing: .secondary
        case .unavailable, .failed: AppTheme.highlight
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private struct PanoramaOutputSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("文件格式", selection: $settings.panoramaFormat) {
                    ForEach(PanoramaImageFormat.allCases) { format in
                        VStack(alignment: .leading) {
                            Text(format.title)
                            Text(format.detail)
                        }
                        .tag(format)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("设置只影响之后生成的全景，不会转换已有文件。HEIC 更适合在 Apple 设备间保存，JPEG 更便于导出到其他软件。")
            }

            Section {
                Picker("全景分辨率", selection: $settings.panoramaResolution) {
                    ForEach(PanoramaResolution.allCases) { resolution in
                        Text("\(resolution.title)  \(resolution.detail)")
                            .tag(resolution)
                    }
                }
                .pickerStyle(.inline)
            } footer: {
                Text("更高分辨率需要更多生成时间、内存和 iCloud 空间。6K 是画质与资源占用的推荐平衡。")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("压缩画质")
                        Spacer()
                        Text("\(Int(settings.panoramaQuality * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.panoramaQuality, in: 0.80...1, step: 0.01)
                }
            } footer: {
                Text("提高画质会增大文件体积，但不会改善采集时产生的视差或运动模糊。")
            }
        }
        .navigationTitle("全景文件")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DataAndPrivacyView: View {
    var body: some View {
        List {
            PrivacyExplanationRow(
                icon: "iphone",
                title: "本地优先",
                detail: "关闭 iCloud 同步时，场景索引和全景文件只保存在这台设备的应用沙盒。"
            )
            PrivacyExplanationRow(
                icon: "icloud",
                title: "由你决定同步",
                detail: "只有开启 iCloud 数据同步后，应用才会读写自己的 iCloud Drive 目录。"
            )
            PrivacyExplanationRow(
                icon: "camera",
                title: "空间数据较敏感",
                detail: "相机画面可能包含住宅、人员或物品信息。分享或导出前请检查内容。"
            )
            PrivacyExplanationRow(
                icon: "cube.transparent",
                title: "未来数据分层保存",
                detail: "后续的关键帧、深度、网格与派生模型会分别管理，并提供独立的存储和同步选项。"
            )
        }
        .navigationTitle("数据说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsAboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppTheme.highlight)
                Text("再次走进，曾经在场的空间。")
                    .font(.largeTitle.bold())
                Text("回见目前支持固定点 360° 全景采集与浏览。连续自由移动的 6DoF 空间、深度与网格持久化、空间标注和高质量重建仍在规划与开发中。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                SettingsSummaryRow(icon: "view.360", title: "当前能力", detail: "定点与多点全景、环视、缩放和本地保存")
                SettingsSummaryRow(icon: "point.3.connected.trianglepath.dotted", title: "演进方向", detail: "可恢复采集包、空间网格、标注与有限范围 6DoF")
                SettingsSummaryRow(icon: "lock.shield", title: "隐私原则", detail: "最少采集、本地优先、云端同步由用户开启")
            }
            .padding(24)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("关于回见")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsSummaryRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.highlight)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PrivacyExplanationRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.highlight)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}
