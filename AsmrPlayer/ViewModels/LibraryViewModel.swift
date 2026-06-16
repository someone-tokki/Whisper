import Foundation
import UIKit

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var currentDirectory: URL
    @Published private(set) var items: [LibraryItem] = []
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published private(set) var isSelecting = false
    @Published private(set) var selectedItemPaths: Set<String> = []
    @Published private(set) var clipboard: LibraryClipboard?
    @Published private(set) var searchableItems: [LibraryItem] = []

    private let fileManager = FileManager.default
    private let subtitleMemoryStore = SubtitleMemoryStore()
    private var lastDirectorySignature = ""
    private var lastRootSignature = ""
    private var syncTask: Task<Void, Never>?
    private var searchIndexTask: Task<Void, Never>?

    init() {
        currentDirectory = Self.documentsDirectory()
        refresh()
        startExternalFolderSync()
    }

    deinit {
        syncTask?.cancel()
        searchIndexTask?.cancel()
    }

    var rootDirectory: URL {
        Self.documentsDirectory()
    }

    var mediaDirectory: URL {
        rootDirectory.appendingPathComponent("media", isDirectory: true)
    }

    var subtitleDirectory: URL {
        rootDirectory.appendingPathComponent("subtitle", isDirectory: true)
    }

    var canGoBack: Bool {
        normalized(currentDirectory.path) != normalized(rootDirectory.path)
    }

    var directoryTitle: String {
        canGoBack ? currentDirectory.lastPathComponent : "本地"
    }

    var breadcrumbs: String {
        guard canGoBack else { return "我的 iPhone > Whisper" }
        let relative = currentDirectory.path.replacingOccurrences(of: rootDirectory.path, with: "")
            .split(separator: "/")
            .joined(separator: " > ")
        return "我的 iPhone > Whisper > \(relative)"
    }

    var mediaItems: [LibraryItem] {
        allItems(kind: .media)
    }

    var subtitleItems: [LibraryItem] {
        allItems(kind: .subtitle)
    }

    func refresh() {
        do {
            try ensureRootDirectory()
            items = try scan(directory: currentDirectory)
            lastDirectorySignature = directorySignature(for: currentDirectory)
            lastRootSignature = directorySignature(for: rootDirectory)
            scheduleSearchIndexRefresh()
        } catch {
            errorMessage = "无法读取资料库：\(error.localizedDescription)"
        }
    }

    func refreshSearchIndex() {
        scheduleSearchIndexRefresh()
    }

    func enter(_ item: LibraryItem) {
        guard item.kind == .folder else { return }
        clearSelection()
        currentDirectory = item.url
        refresh()
    }

    func goBack() {
        guard canGoBack else { return }
        clearSelection()
        currentDirectory.deleteLastPathComponent()
        refresh()
    }

    func goRoot() {
        clearSelection()
        currentDirectory = rootDirectory
        refresh()
    }

    func enterFolder(url: URL) {
        guard isDirectory(url), isInsideRoot(url) else { return }
        clearSelection()
        currentDirectory = url
        refresh()
    }

    func revealStorageLocation() {
        #if os(iOS)
        guard let filesURL = URL(string: "shareddocuments://") else {
            errorMessage = "无法打开文件 App，请手动前往“文件 > 我的 iPhone > Whisper”。"
            return
        }

        let encodedPath = rootDirectory.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rootDirectory.path
        let exactFilesURL = URL(string: "shareddocuments://\(encodedPath)")
        UIApplication.shared.open(exactFilesURL ?? filesURL) { [weak self] success in
            guard !success else { return }
            UIApplication.shared.open(filesURL) { [weak self] fallbackSuccess in
                guard !fallbackSuccess else { return }
                Task { @MainActor [weak self] in
                    self?.errorMessage = "无法打开文件 App，请手动前往“文件 > 我的 iPhone > Whisper”。"
                }
            }
        }
        #endif
    }

    func importMedia(from url: URL, player: PlayerViewModel) {
        player.subtitleAutoloadHandler = { [weak self, weak player] mediaURL in
            guard let self, let player else { return }
            self.autoLoadSubtitle(for: mediaURL, player: player)
        }
        player.setPlaybackQueue(playbackQueue(for: url))
        player.openMedia(url: url)
    }

    func importPlaylistMedia(from url: URL, queue: PlaybackQueue, player: PlayerViewModel) {
        player.subtitleAutoloadHandler = { [weak self, weak player] mediaURL in
            guard let self, let player else { return }
            self.autoLoadSubtitle(for: mediaURL, player: player)
        }
        player.setPlaybackQueue(queue)
        player.openMedia(url: url)
    }

    func importSubtitle(from url: URL, player: PlayerViewModel) {
        player.openSubtitle(url: url)
        if let mediaURL = player.state.sourceURL {
            subtitleMemoryStore.save(subtitle: url, for: mediaURL)
        }
    }

    func createFolder(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let url = uniqueFolder(named: name, in: currentDirectory)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            refresh()
        } catch {
            errorMessage = "新建文件夹失败：\(error.localizedDescription)"
        }
    }

    func delete(_ item: LibraryItem) {
        do {
            try removeItem(at: item.url)
            refresh()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    var selectedItems: [LibraryItem] {
        items.filter { selectedItemPaths.contains(pathKey(for: $0.url)) }
    }

    var selectedCount: Int {
        selectedItemPaths.count
    }

    var allCurrentPageSelected: Bool {
        !items.isEmpty && items.allSatisfy { selectedItemPaths.contains(pathKey(for: $0.url)) }
    }

    var canPaste: Bool {
        clipboard != nil
    }

    var copiedMediaURLs: [URL] {
        guard clipboard?.operation == .copy else { return [] }
        return clipboard?.items.filter { MediaLibrary.mediaExtensions.contains($0.pathExtension.lowercased()) } ?? []
    }

    func isSelected(_ item: LibraryItem) -> Bool {
        selectedItemPaths.contains(pathKey(for: item.url))
    }

    func beginSelection(with item: LibraryItem) {
        isSelecting = true
        selectedItemPaths = [pathKey(for: item.url)]
    }

    func toggleSelectionMode() {
        if isSelecting {
            clearSelection()
        } else {
            isSelecting = true
        }
    }

    func toggleSelection(_ item: LibraryItem) {
        let key = pathKey(for: item.url)
        if selectedItemPaths.contains(key) {
            selectedItemPaths.remove(key)
        } else {
            selectedItemPaths.insert(key)
        }
    }

    func toggleSelectAllCurrentPage() {
        guard !items.isEmpty else { return }
        if allCurrentPageSelected {
            selectedItemPaths.removeAll()
        } else {
            selectedItemPaths = Set(items.map { pathKey(for: $0.url) })
        }
        isSelecting = true
    }

    func copySelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboard = LibraryClipboard(operation: .copy, items: urls)
        setStatusMessage("已复制 \(urls.count) 个项目")
    }

    func cutSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboard = LibraryClipboard(operation: .cut, items: urls)
        setStatusMessage("已剪切 \(urls.count) 个项目")
    }

    func pasteClipboard() {
        guard let clipboard else { return }
        do {
            try paste(clipboard)
            if clipboard.operation == .cut {
                self.clipboard = nil
            }
            refresh()
            setStatusMessage("已粘贴 \(clipboard.items.count) 个项目")
        } catch {
            errorMessage = "粘贴失败：\(error.localizedDescription)"
        }
    }

    func deleteSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        do {
            for url in urls {
                try removeItem(at: url)
            }
            clearSelection()
            refresh()
            setStatusMessage("已删除 \(urls.count) 个项目")
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    func clearSelection() {
        isSelecting = false
        selectedItemPaths.removeAll()
    }

    func subtitleBrowserItems(in directory: URL) -> [LibraryItem] {
        do {
            return try scan(directory: directory).filter { item in
                item.kind == .folder || item.kind == .subtitle
            }
        } catch {
            errorMessage = "无法读取字幕目录：\(error.localizedDescription)"
            return []
        }
    }

    func mediaBrowserItems(in directory: URL) -> [LibraryItem] {
        do {
            return try scan(directory: directory).filter { item in
                item.kind == .folder || item.kind == .media
            }
        } catch {
            errorMessage = "无法读取媒体目录：\(error.localizedDescription)"
            return []
        }
    }

    func defaultSubtitleDirectory(for mediaURL: URL?) -> URL {
        guard let mediaURL else { return rootDirectory }
        let directory = mediaURL.deletingLastPathComponent()
        guard isInsideRoot(directory), isDirectory(directory) else { return rootDirectory }
        return directory
    }

    func canGoBack(from directory: URL) -> Bool {
        normalized(directory.path) != normalized(rootDirectory.path)
    }

    func parentDirectory(of directory: URL) -> URL {
        guard canGoBack(from: directory) else { return rootDirectory }
        return directory.deletingLastPathComponent()
    }

    func breadcrumbs(for directory: URL) -> String {
        guard canGoBack(from: directory) else { return "我的 iPhone > Whisper" }
        let relative = directory.path.replacingOccurrences(of: rootDirectory.path, with: "")
            .split(separator: "/")
            .joined(separator: " > ")
        return "我的 iPhone > Whisper > \(relative)"
    }

    private func ensureRootDirectory() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try ensureInitialDefaultFoldersIfNeeded()
    }

    private func ensureInitialDefaultFoldersIfNeeded() throws {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.defaultFoldersCreatedKey) else { return }
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: subtitleDirectory, withIntermediateDirectories: true)
        defaults.set(true, forKey: Self.defaultFoldersCreatedKey)
    }

    private func scan(directory: URL) throws -> [LibraryItem] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap(makeItem)
            .sorted { lhs, rhs in
                if lhs.kind == .folder && rhs.kind != .folder { return true }
                if lhs.kind != .folder && rhs.kind == .folder { return false }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private func startExternalFolderSync() {
        syncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.refreshIfDirectoryChanged()
            }
        }
    }

    private func refreshIfDirectoryChanged() {
        let signature = directorySignature(for: currentDirectory)
        let rootSignature = directorySignature(for: rootDirectory)
        if rootSignature != lastRootSignature {
            lastRootSignature = rootSignature
            scheduleSearchIndexRefresh()
        }
        guard signature != lastDirectorySignature else { return }
        refresh()
    }

    private func allItems(kind: LibraryItem.Kind) -> [LibraryItem] {
        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { element in
            guard let url = element as? URL, let item = makeItem(url), item.kind == kind else { return nil }
            return item
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func scheduleSearchIndexRefresh() {
        let rootDirectory = rootDirectory
        searchIndexTask?.cancel()
        searchIndexTask = Task { [weak self] in
            let items = await Task.detached(priority: .utility) {
                SearchIndexBuilder.items(in: rootDirectory)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.searchableItems = items
            }
        }
    }

    private func playbackQueue(for url: URL) -> PlaybackQueue {
        let directory = url.deletingLastPathComponent()
        let mediaKind = PlaybackMediaKind(url: url)
        let items = (try? scan(directory: directory))?
            .filter { $0.kind == .media && mediaKind.matches($0.url) }
            .map(\.url) ?? [url]

        return PlaybackQueue(
            source: .folder(directory),
            mediaKind: mediaKind,
            items: items.isEmpty ? [url] : items,
            currentURL: url
        )
    }

    private func paste(_ clipboard: LibraryClipboard) throws {
        for source in clipboard.items {
            let destination = uniqueDestinationURL(for: source, in: currentDirectory)
            guard !isSameOrAncestor(source, destination: destination) else { continue }

            switch clipboard.operation {
            case .copy:
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
            case .cut:
                if normalized(source.path) == normalized(destination.path) {
                    continue
                }
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: source, to: destination)
            }
        }
    }

    private func removeItem(at url: URL) throws {
        if isDirectory(url) {
            removeStoredMetadata(inside: url)
        } else {
            removeStoredMetadata(for: url)
        }
        try fileManager.removeItem(at: url)
    }

    private func removeStoredMetadata(inside directory: URL) {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            removeStoredMetadata(for: url)
        }
    }

    private func removeStoredMetadata(for url: URL) {
        let ext = url.pathExtension.lowercased()
        guard MediaLibrary.mediaExtensions.contains(ext) else { return }
        PlaybackProgressStore.shared.remove(for: url)
        VideoMetadataStore.shared.remove(for: url)
    }

    private func autoLoadSubtitle(for mediaURL: URL, player: PlayerViewModel) {
        if let remembered = subtitleMemoryStore.subtitle(for: mediaURL),
           fileManager.fileExists(atPath: remembered.path) {
            if player.openSubtitle(url: remembered, reportsErrors: false) {
                player.statusMessage = "自动匹配字幕：\(remembered.lastPathComponent)"
                return
            }
        }

        let subtitleURLs = allItems(kind: .subtitle).map(\.url)
        for match in SubtitleMatcher.rankedMatches(
            for: mediaURL,
            subtitles: subtitleURLs,
            preferredLanguage: AppSettings.shared.preferredSubtitleLanguage
        ).prefix(5) {
            if player.openSubtitle(url: match.url, reportsErrors: false) {
                subtitleMemoryStore.save(subtitle: match.url, for: mediaURL)
                player.statusMessage = "自动匹配字幕：\(match.url.lastPathComponent)"
                return
            }
        }
    }

    private func makeItem(_ url: URL) -> LibraryItem? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
        let isDirectory = values?.isDirectory == true
        let kind = kind(for: url, isDirectory: isDirectory)
        guard kind != .other || !isDirectory else { return nil }
        let childCount = isDirectory ? ((try? fileManager.contentsOfDirectory(atPath: url.path).count) ?? 0) : nil

        return LibraryItem(
            id: url,
            url: url,
            kind: kind,
            title: isDirectory ? url.lastPathComponent : MediaLibrary.displayName(for: url),
            fileExtension: url.pathExtension.uppercased(),
            fileSize: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate ?? .distantPast,
            childCount: childCount
        )
    }

    private func kind(for url: URL, isDirectory: Bool) -> LibraryItem.Kind {
        if isDirectory { return .folder }
        let ext = url.pathExtension.lowercased()
        if MediaLibrary.mediaExtensions.contains(ext) { return .media }
        if MediaLibrary.subtitleExtensions.contains(ext) { return .subtitle }
        if MediaLibrary.imageExtensions.contains(ext) { return .image }
        if MediaLibrary.documentExtensions.contains(ext) { return .document }
        return .other
    }

    private func uniqueFolder(named name: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(name, isDirectory: true)
        var count = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name)-\(count)", isDirectory: true)
            count += 1
        }
        return candidate
    }

    private func uniqueDestinationURL(for source: URL, in directory: URL) -> URL {
        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let fileName = isDirectory ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        let fileExtension = isDirectory ? "" : source.pathExtension
        var candidate = destinationURL(named: fileName, extension: fileExtension, isDirectory: isDirectory, in: directory)
        var count = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = destinationURL(named: "\(fileName)-\(count)", extension: fileExtension, isDirectory: isDirectory, in: directory)
            count += 1
        }
        return candidate
    }

    private func destinationURL(named name: String, extension fileExtension: String, isDirectory: Bool, in directory: URL) -> URL {
        if isDirectory {
            return directory.appendingPathComponent(name, isDirectory: true)
        }
        if fileExtension.isEmpty {
            return directory.appendingPathComponent(name)
        }
        return directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
    }

    private func isSameOrAncestor(_ source: URL, destination: URL) -> Bool {
        let sourcePath = normalized(source.path)
        let destinationPath = normalized(destination.path)
        return destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/")
    }

    private func pathKey(for url: URL) -> String {
        normalized(url.path)
    }

    private func setStatusMessage(_ text: String) {
        statusMessage = text
        errorMessage = nil
    }

    private func directorySignature(for directory: URL) -> String {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ""
        }

        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values?.fileSize ?? 0
            let directoryFlag = values?.isDirectory == true ? "d" : "f"
            return "\(url.lastPathComponent):\(directoryFlag):\(size):\(modified)"
        }
        .sorted()
        .joined(separator: "|")
    }

    private func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        normalized(url.path).hasPrefix(normalized(rootDirectory.path))
    }

    private func isSearchableFolder(_ item: LibraryItem) -> Bool {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !MediaLibrary.mediaExtensions.contains(title) && !MediaLibrary.subtitleExtensions.contains(title)
    }

    private static func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static let defaultFoldersCreatedKey = "library.defaultFoldersCreated"
}

struct LibraryClipboard {
    enum Operation {
        case copy
        case cut
    }

    let operation: Operation
    let items: [URL]
}

private final class SubtitleMemoryStore {
    private let fileURL: URL
    private let lock = NSLock()
    private var cache: [String: String]

    init() {
        let fileManager = FileManager.default
        fileURL = AppStorageLocation.applicationSupportDirectory
            .appendingPathComponent("subtitle-matches.plist")
        let legacyURL = fileManager
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("subtitle-matches.plist")
        if fileManager.fileExists(atPath: legacyURL.path),
           !fileManager.fileExists(atPath: fileURL.path) {
            try? AppStorageLocation.ensureDirectory(for: fileURL)
            try? fileManager.moveItem(at: legacyURL, to: fileURL)
        } else if fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.removeItem(at: legacyURL)
        }
        cache = (NSDictionary(contentsOf: fileURL) as? [String: String]) ?? [:]
    }

    func subtitle(for mediaURL: URL) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = cache[key(for: mediaURL)] else { return nil }
        return URL(fileURLWithPath: value)
    }

    func save(subtitle: URL, for mediaURL: URL) {
        lock.lock()
        cache[key(for: mediaURL)] = subtitle.path
        let snapshot = cache
        lock.unlock()
        try? AppStorageLocation.ensureDirectory(for: fileURL)
        (snapshot as NSDictionary).write(to: fileURL, atomically: true)
    }

    private func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}

private enum SearchIndexBuilder {
    static func items(in rootDirectory: URL) -> [LibraryItem] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { element in
            guard !Task.isCancelled,
                  let url = element as? URL,
                  let item = makeItem(url, fileManager: fileManager) else {
                return nil
            }

            switch item.kind {
            case .folder:
                return isSearchableFolder(item) ? item : nil
            case .media, .subtitle, .image, .document, .other:
                return item
            }
        }
        .sorted { lhs, rhs in
            if lhs.kind == .folder && rhs.kind != .folder { return true }
            if lhs.kind != .folder && rhs.kind == .folder { return false }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private static func makeItem(_ url: URL, fileManager: FileManager) -> LibraryItem? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
        let isDirectory = values?.isDirectory == true
        let kind = kind(for: url, isDirectory: isDirectory)
        guard kind != .other || !isDirectory else { return nil }
        let childCount = isDirectory ? ((try? fileManager.contentsOfDirectory(atPath: url.path).count) ?? 0) : nil

        return LibraryItem(
            id: url,
            url: url,
            kind: kind,
            title: isDirectory ? url.lastPathComponent : MediaLibrary.displayName(for: url),
            fileExtension: url.pathExtension.uppercased(),
            fileSize: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate ?? .distantPast,
            childCount: childCount
        )
    }

    private static func kind(for url: URL, isDirectory: Bool) -> LibraryItem.Kind {
        if isDirectory { return .folder }
        let ext = url.pathExtension.lowercased()
        if MediaLibrary.mediaExtensions.contains(ext) { return .media }
        if MediaLibrary.subtitleExtensions.contains(ext) { return .subtitle }
        if MediaLibrary.imageExtensions.contains(ext) { return .image }
        if MediaLibrary.documentExtensions.contains(ext) { return .document }
        return .other
    }

    private static func isSearchableFolder(_ item: LibraryItem) -> Bool {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !MediaLibrary.mediaExtensions.contains(title) && !MediaLibrary.subtitleExtensions.contains(title)
    }
}
