import Foundation

protocol SettingsStoring: AnyObject {
    func load() -> RecordingSettings
    func save(_ settings: RecordingSettings)
}

final class UserDefaultsSettingsStore: SettingsStoring {
    private enum Key {
        static let recordingSettings = "recordingSettings.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> RecordingSettings {
        guard
            let data = defaults.data(forKey: Key.recordingSettings),
            let settings = try? decoder.decode(RecordingSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    func save(_ settings: RecordingSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }
        defaults.set(data, forKey: Key.recordingSettings)
    }
}

final class InMemorySettingsStore: SettingsStoring {
    private(set) var value: RecordingSettings

    init(value: RecordingSettings = .default) {
        self.value = value
    }

    func load() -> RecordingSettings {
        value
    }

    func save(_ settings: RecordingSettings) {
        value = settings
    }
}
