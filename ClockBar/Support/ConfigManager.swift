import Foundation

enum ConfigManager {
    static func load() -> ClockConfig {
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder.clockStore.decode(ClockConfig.self, from: data)
        else {
            return .default
        }

        return config
    }

    static func save(_ config: ClockConfig) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder.clockStore.encode(config)
        try data.write(to: configPath, options: .atomic)
    }
}
