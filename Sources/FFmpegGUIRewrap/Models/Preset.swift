import Foundation

struct Preset: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var description: String
    var settings: JobSettings
    var isBuiltIn: Bool = false

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Preset, rhs: Preset) -> Bool { lhs.id == rhs.id }
}

@Observable
class PresetManager {
    var presets: [Preset] = []

    private let storageURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("FFmpegGUI-Rewrap/Presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("presets.json")
    }()

    init() {
        loadBuiltIn()
        loadUserPresets()
    }

    // MARK: - Persistence

    func save(_ preset: Preset) {
        if let i = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[i] = preset
        } else {
            presets.append(preset)
        }
        persistUserPresets()
    }

    func delete(_ preset: Preset) {
        guard !preset.isBuiltIn else { return }
        presets.removeAll { $0.id == preset.id }
        persistUserPresets()
    }

    private func persistUserPresets() {
        let userPresets = presets.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(userPresets) {
            try? data.write(to: storageURL)
        }
    }

    private func loadUserPresets() {
        guard let data = try? Data(contentsOf: storageURL),
              let loaded = try? JSONDecoder().decode([Preset].self, from: data) else { return }
        presets.append(contentsOf: loaded)
    }

    private func loadBuiltIn() {
        presets = BuiltinPresets.all
    }

    func exportJSON(_ preset: Preset) -> String? {
        guard let data = try? JSONEncoder().encode(preset) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func importJSON(_ json: String) throws -> Preset {
        guard let data = json.data(using: .utf8) else {
            throw ImportError.invalidData
        }
        var preset = try JSONDecoder().decode(Preset.self, from: data)
        preset.id = UUID()       // always fresh ID on import
        preset.isBuiltIn = false
        save(preset)
        return preset
    }

    enum ImportError: LocalizedError {
        case invalidData
        var errorDescription: String? { "Could not parse preset JSON" }
    }

    var userPresets: [Preset]   { presets.filter { !$0.isBuiltIn } }
    var builtInPresets: [Preset] { presets.filter { $0.isBuiltIn } }
}
