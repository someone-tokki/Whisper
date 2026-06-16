import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var videoMetadata = VideoMetadataStore.shared
    @StateObject private var progressStore = PlaybackProgressStore.shared
    var openLibrary: () -> Void = {}
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var queryDebounceTask: Task<Void, Never>?

    private var filteredResults: [LibraryItem] {
        let text = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.searchableItems.filter {
            settings.allowsSearchResult(kind: $0.kind, fileExtension: $0.fileExtension)
                && (text.isEmpty
                    || $0.title.localizedCaseInsensitiveContains(text)
                    || $0.fileExtension.localizedCaseInsensitiveContains(text))
        }
    }

    private var sections: [SearchResultSection] {
        let grouped = Dictionary(grouping: filteredResults) {
            SearchFilter(kind: $0.kind, fileExtension: $0.fileExtension)
        }
        return SearchFilter.allCases.compactMap { filter in
            guard let items = grouped[filter], !items.isEmpty else { return nil }
            return SearchResultSection(filter: filter, items: items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if sections.isEmpty {
                    Section("无结果") {
                        Text("没有找到匹配的项目")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(sections) { section in
                    Section(section.filter.title) {
                        ForEach(section.items) { item in
                            searchResultButton(for: item)
                        }
                    }
                }
            }
            .navigationTitle("搜索")
            .searchable(text: $query, prompt: "搜索文件或文件夹")
            .onAppear {
                debouncedQuery = query
                library.refreshSearchIndex()
            }
            .onChange(of: query) { _, newValue in
                queryDebounceTask?.cancel()
                queryDebounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    debouncedQuery = newValue
                }
            }
            .onDisappear {
                queryDebounceTask?.cancel()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultButton(for item: LibraryItem) -> some View {
        Button {
            open(item)
        } label: {
            SearchResultRow(
                item: item,
                videoMetadata: videoMetadata.metadata(for: item.url),
                progress: progressStore.record(for: item.url)
            )
        }
        .disabled(item.kind == .image || item.kind == .document || item.kind == .other)
    }

    private func open(_ item: LibraryItem) {
        switch item.kind {
        case .folder:
            library.enterFolder(url: item.url)
            openLibrary()
            dismiss()
        case .media:
            library.importMedia(from: item.url, player: player)
            player.play()
            dismiss()
        case .subtitle:
            library.importSubtitle(from: item.url, player: player)
            dismiss()
        case .image, .document, .other:
            break
        }
    }
}

private struct SearchResultSection: Identifiable {
    let filter: SearchFilter
    let items: [LibraryItem]

    var id: SearchFilter { filter }
}

private struct SearchResultRow: View {
    let item: LibraryItem
    let videoMetadata: VideoMetadata?
    let progress: PlaybackProgressRecord?

    var body: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let progress, item.kind == .media, progress.progress > 0, !progress.completed {
                    ProgressView(value: progress.progress)
                        .tint(.yellow)
                        .frame(height: 3)
                }
            }
        }
        .onAppear {
            VideoMetadataStore.shared.loadIfNeeded(for: item.url)
        }
    }

    private var icon: some View {
        ZStack {
            if videoMetadata?.thumbnailURL != nil,
               let image = VideoMetadataStore.shared.cachedThumbnail(for: item.url) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
            }
        }
        .frame(width: 44, height: 34)
    }

    private var iconName: String {
        if item.kind == .folder {
            return "folder"
        }
        switch item.kind {
        case .media:
            return MediaLibrary.isVideoExtension(item.fileExtension) ? "film.fill" : "waveform"
        case .subtitle:
            return "captions.bubble"
        case .image:
            return "photo"
        case .document:
            return "doc.text"
        case .folder:
            return "folder"
        case .other:
            return "doc"
        }
    }

    private var iconColor: Color {
        if item.kind == .folder {
            return .yellow
        }
        switch item.kind {
        case .media:
            return MediaLibrary.isVideoExtension(item.fileExtension) ? .purple : .red
        case .subtitle:
            return .blue
        case .image:
            return .green
        case .document:
            return .purple
        case .folder:
            return .yellow
        case .other:
            return .secondary
        }
    }

    private var detailText: String {
        if item.kind == .folder {
            return "\(item.childCount ?? 0) 个项目"
        }
        let duration = videoMetadata?.duration.map { "\(formatTime($0)) · " } ?? ""
        return "\(duration)\(item.fileExtension) · \(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))"
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
