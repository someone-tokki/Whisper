import Foundation
import SwiftUI

@MainActor
final class PlaylistStore: ObservableObject {
    @Published private(set) var playlists: [Playlist] = []
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let fileManager = FileManager.default
    private let storageURL: URL

    init() {
        storageURL = AppStorageLocation.applicationSupportDirectory
            .appendingPathComponent("playlists.json")
        load()
    }

    func refresh() {
        load()
    }

    func playlist(id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    func createPlaylist(name rawName: String, note rawNote: String) -> Playlist? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let playlist = Playlist(
            name: uniquePlaylistName(for: name),
            note: note,
            itemPaths: []
        )
        playlists.insert(playlist, at: 0)
        save()
        setStatusMessage("已创建播放列表")
        return playlist
    }

    func updatePlaylist(id: UUID, name rawName: String, note rawNote: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        playlists[index].name = uniquePlaylistName(for: name, excluding: id)
        playlists[index].note = note
        playlists[index].updatedAt = .now
        save()
    }

    func deletePlaylist(id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists.remove(at: index)
        save()
        setStatusMessage("已删除播放列表")
    }

    func deletePlaylists(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        playlists.removeAll { ids.contains($0.id) }
        save()
        setStatusMessage("已删除 \(ids.count) 个播放列表")
    }

    func addMedia(to playlistID: UUID, urls: [URL]) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let normalized = Set(playlists[index].itemPaths)
        let additions = urls
            .map { $0.standardizedFileURL.path }
            .filter { !normalized.contains($0) }

        guard !additions.isEmpty else { return }
        playlists[index].itemPaths.append(contentsOf: additions)
        playlists[index].updatedAt = .now
        save()
        setStatusMessage("已添加 \(additions.count) 个媒体")
    }

    func appendMedia(to playlistID: UUID, urls: [URL]) {
        addMedia(to: playlistID, urls: urls)
    }

    func removeMedia(from playlistID: UUID, at offsets: IndexSet) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].itemPaths.remove(atOffsets: offsets)
        playlists[index].updatedAt = .now
        save()
    }

    func removeMedia(from playlistID: UUID, paths: Set<String>) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }), !paths.isEmpty else { return }
        playlists[index].itemPaths.removeAll { paths.contains($0) }
        playlists[index].updatedAt = .now
        save()
        setStatusMessage("已从播放列表移除 \(paths.count) 个媒体")
    }

    func replaceMedia(in playlistID: UUID, with urls: [URL]) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].itemPaths = uniquePaths(from: urls)
        playlists[index].updatedAt = .now
        save()
    }

    func moveMedia(in playlistID: UUID, from source: IndexSet, to destination: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].itemPaths.move(fromOffsets: source, toOffset: destination)
        playlists[index].updatedAt = .now
        save()
    }

    func selectAllItems(in playlistID: UUID) -> Set<String> {
        guard let playlist = playlist(id: playlistID) else { return [] }
        return Set(playlist.itemPaths)
    }

    func playbackQueue(for playlistID: UUID, currentURL: URL? = nil) -> PlaybackQueue? {
        guard let playlist = playlist(id: playlistID) else { return nil }
        let urls = playlist.itemPaths
            .map(URL.init(fileURLWithPath:))
            .filter { fileManager.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return nil }
        let current = currentURL ?? urls.first
        return PlaybackQueue(
            source: .playlist(playlistID.uuidString),
            mediaKind: current.map(PlaybackMediaKind.init(url:)),
            items: urls,
            currentURL: current
        )
    }

    func urls(for playlistID: UUID) -> [URL] {
        guard let playlist = playlist(id: playlistID) else { return [] }
        return playlist.itemPaths.map(URL.init(fileURLWithPath:))
    }

    func contains(_ url: URL, in playlistID: UUID) -> Bool {
        guard let playlist = playlist(id: playlistID) else { return false }
        return playlist.itemPaths.contains(url.standardizedFileURL.path)
    }

    func indexOfPlaylistItem(url: URL, in playlistID: UUID) -> Int? {
        guard let playlist = playlist(id: playlistID) else { return nil }
        return playlist.itemPaths.firstIndex(of: url.standardizedFileURL.path)
    }

    func insertMedia(into playlistID: UUID, urls: [URL], at index: Int? = nil) {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let additions = uniquePaths(from: urls)
        guard !additions.isEmpty else { return }

        var itemPaths = playlists[playlistIndex].itemPaths
        let insertIndex = min(max(index ?? itemPaths.count, 0), itemPaths.count)
        itemPaths.insert(contentsOf: additions, at: insertIndex)
        playlists[playlistIndex].itemPaths = deduplicated(itemPaths)
        playlists[playlistIndex].updatedAt = .now
        save()
        setStatusMessage("已添加 \(additions.count) 个媒体")
    }

    private func uniquePlaylistName(for name: String, excluding excludedID: UUID? = nil) -> String {
        var candidate = name
        var suffix = 1
        let existing = Set(playlists.filter { $0.id != excludedID }.map(\.name))
        while existing.contains(candidate) {
            candidate = "\(name)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func uniquePaths(from urls: [URL]) -> [String] {
        deduplicated(urls.map { $0.standardizedFileURL.path })
    }

    private func deduplicated(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            playlists = []
            return
        }

        do {
            playlists = try JSONDecoder().decode([Playlist].self, from: data)
        } catch {
            playlists = []
            errorMessage = "无法读取播放列表：\(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(playlists)
            try AppStorageLocation.ensureDirectory(for: storageURL)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            errorMessage = "无法保存播放列表：\(error.localizedDescription)"
        }
    }

    private func setStatusMessage(_ text: String) {
        statusMessage = text
        errorMessage = nil
    }
}
