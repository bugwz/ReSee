import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .simplifiedChinese: "简体中文"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: nil
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum PanoramaImageFormat: String, CaseIterable, Identifiable {
    case heic
    case jpeg

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }

    var detail: String {
        switch self {
        case .heic: "文件更小，保留较高画质"
        case .jpeg: "兼容更多设备和软件"
        }
    }
}

enum PanoramaResolution: Int, CaseIterable, Identifiable {
    case compact = 4096
    case standard = 6144
    case high = 8192

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .compact: "4K"
        case .standard: "6K"
        case .high: "8K"
        }
    }

    var detail: String { "\(rawValue) × \(rawValue / 2)" }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var isICloudSyncEnabled: Bool { didSet { persist() } }
    @Published var language: AppLanguage { didSet { persist() } }
    @Published var appearance: AppAppearance { didSet { persist() } }
    @Published var panoramaFormat: PanoramaImageFormat { didSet { persist() } }
    @Published var panoramaResolution: PanoramaResolution { didSet { persist() } }
    @Published var panoramaQuality: Double { didSet { persist() } }
    @Published var isCaptureHapticsEnabled: Bool { didSet { persist() } }
    @Published var keepsScreenAwakeDuringCapture: Bool { didSet { persist() } }
    @Published var isMotionViewingEnabled: Bool { didSet { persist() } }

    private let defaults: UserDefaults
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isICloudSyncEnabled = defaults.bool(forKey: Keys.iCloudSync)
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        panoramaFormat = PanoramaImageFormat(
            rawValue: defaults.string(forKey: Keys.panoramaFormat) ?? ""
        ) ?? .heic
        panoramaResolution = PanoramaResolution(
            rawValue: defaults.object(forKey: Keys.panoramaResolution) as? Int ?? 6144
        ) ?? .standard
        let storedQuality = defaults.object(forKey: Keys.panoramaQuality) as? Double
        panoramaQuality = storedQuality.map { min(max($0, 0.75), 1) } ?? 0.94
        isCaptureHapticsEnabled = defaults.object(forKey: Keys.captureHaptics) as? Bool ?? true
        keepsScreenAwakeDuringCapture = defaults.object(forKey: Keys.keepAwake) as? Bool ?? true
        isMotionViewingEnabled = defaults.object(forKey: Keys.motionViewing) as? Bool ?? true
        isLoading = false
    }

    private func persist() {
        guard !isLoading else { return }
        defaults.set(isICloudSyncEnabled, forKey: Keys.iCloudSync)
        defaults.set(language.rawValue, forKey: Keys.language)
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
        defaults.set(panoramaFormat.rawValue, forKey: Keys.panoramaFormat)
        defaults.set(panoramaResolution.rawValue, forKey: Keys.panoramaResolution)
        defaults.set(panoramaQuality, forKey: Keys.panoramaQuality)
        defaults.set(isCaptureHapticsEnabled, forKey: Keys.captureHaptics)
        defaults.set(keepsScreenAwakeDuringCapture, forKey: Keys.keepAwake)
        defaults.set(isMotionViewingEnabled, forKey: Keys.motionViewing)
    }

    private enum Keys {
        static let iCloudSync = "settings.icloud-sync"
        static let language = "settings.language"
        static let appearance = "settings.appearance"
        static let panoramaFormat = "settings.panorama-format"
        static let panoramaResolution = "settings.panorama-resolution"
        static let panoramaQuality = "settings.panorama-quality"
        static let captureHaptics = "settings.capture-haptics"
        static let keepAwake = "settings.keep-awake"
        static let motionViewing = "settings.motion-viewing"
    }
}
