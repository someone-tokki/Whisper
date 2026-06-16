import Foundation

struct PlaybackProgressRecord: Codable {
    var position: TimeInterval
    var duration: TimeInterval
    var updatedAt: Date
    var completed: Bool

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}

@MainActor
final class PlaybackProgressStore: ObservableObject {
    static let shared = PlaybackProgressStore()

    @Published private(set) var records: [String: PlaybackProgressRecord]

    private let fileURL: URL
    private var persistTask: Task<Void, Never>?

    private init() {
        fileURL = AppStorageLocation.applicationSupportDirectory
            .appendingPathComponent("playback-progress.plist")

        if let data = try? Data(contentsOf: fileURL),
           let records = try? PropertyListDecoder().decode([String: PlaybackProgressRecord].self, from: data) {
            self.records = records
        } else {
            self.records = [:]
        }
    }

    func record(for url: URL) -> PlaybackProgressRecord? {
        records[key(for: url)]
    }

    func save(position: TimeInterval, duration: TimeInterval, for url: URL) {
        guard duration > 0, position.isFinite else { return }
        let clamped = min(max(position, 0), duration)
        let completed = duration > 8 && duration - clamped < 5
        records[key(for: url)] = PlaybackProgressRecord(
            position: clamped,
            duration: duration,
            updatedAt: Date(),
            completed: completed
        )
        schedulePersist()
    }

    func remove(for url: URL) {
        records.removeValue(forKey: key(for: url))
        persistNow()
    }

    func persistNow() {
        persistTask?.cancel()
        persistTask = nil
        persist(records)
    }

    private func schedulePersist() {
        persistTask?.cancel()
        let snapshot = records
        persistTask = Task.detached(priority: .utility) { [fileURL] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            Self.persist(snapshot, to: fileURL)
        }
    }

    private func persist(_ snapshot: [String: PlaybackProgressRecord]) {
        Self.persist(snapshot, to: fileURL)
    }

    private nonisolated static func persist(_ snapshot: [String: PlaybackProgressRecord], to fileURL: URL) {
        guard let data = try? PropertyListEncoder().encode(snapshot) else { return }
        try? AppStorageLocation.ensureDirectory(for: fileURL)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
