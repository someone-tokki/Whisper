import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var library: LibraryViewModel
    @StateObject private var videoMetadata = VideoMetadataStore.shared
    @StateObject private var progressStore = PlaybackProgressStore.shared
    @Binding var compactChrome: Bool
    @State private var showCreateFolder = false
    @State private var newFolderName = ""
    @State private var confirmDeleteSelection = false
    @State private var previewItem: LibraryItem?
    @State private var lastScrollOffset: CGFloat?
    @State private var accumulatedDragDelta: CGFloat = 0
    @State private var openDeleteRowID: URL?
    private let scrollCoordinateSpaceName = "library-scroll"

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        ChromeLinkedScrollOffsetReader(coordinateSpaceName: scrollCoordinateSpaceName)

                        if library.items.isEmpty {
                            emptyState
                                .padding(.top, 40)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(library.items) { item in
                                    FileManagerRow(
                                        item: item,
                                        isActive: player.state.sourceURL == item.url || player.state.subtitleURL == item.url,
                                        videoMetadata: videoMetadata.metadata(for: item.url),
                                        progress: progressStore.record(for: item.url),
                                        isSelecting: library.isSelecting,
                                        isSelected: library.isSelected(item),
                                        open: {
                                            open(item)
                                        },
                                        toggleSelection: {
                                            library.toggleSelection(item)
                                        },
                                        beginSelection: {
                                            library.beginSelection(with: item)
                                        },
                                        openDeleteRowID: $openDeleteRowID,
                                        delete: {
                                            library.delete(item)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.bottom, compactChrome ? 112 : 178)
                }
                .coordinateSpace(name: scrollCoordinateSpaceName)
                .onPreferenceChange(ChromeScrollOffsetPreferenceKey.self, perform: handleChromeLinkedScroll)
                .background(Color(.systemBackground))
                .simultaneousGesture(
                    TapGesture().onEnded {
                        closeOpenDeleteRow()
                    }
                )
                .navigationTitle(library.directoryTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        leadingToolbarItem
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        trailingToolbarItem
                    }
                }
            }
            .confirmationDialog("删除选中的项目？", isPresented: $confirmDeleteSelection, titleVisibility: .visible) {
                Button("删除 \(library.selectedCount) 个项目", role: .destructive) {
                    library.deleteSelection()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这些文件会从资料库文件夹中删除。")
            }
            .alert("新建文件夹", isPresented: $showCreateFolder) {
                TextField("文件夹名称", text: $newFolderName)
                Button("取消", role: .cancel) {
                    newFolderName = ""
                }
                Button("创建") {
                    library.createFolder(named: newFolderName)
                    newFolderName = ""
                }
            }
            .onAppear {
                library.refresh()
            }
            .sheet(item: $previewItem) { item in
                FilePreviewView(item: item) {
                    library.importSubtitle(from: item.url, player: player)
                }
                .environmentObject(library)
            }
            .edgeBackGesture(isEnabled: library.canGoBack && !library.isSelecting) {
                library.goBack()
            }
        }
    }

    @ViewBuilder
    private var leadingToolbarItem: some View {
        if library.isSelecting {
            Button(library.allCurrentPageSelected ? "取消全选" : "全选") {
                library.toggleSelectAllCurrentPage()
            }
            .tint(.yellow)
            .disabled(library.items.isEmpty)
        } else if library.canGoBack {
            Button {
                library.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tint(.yellow)
            .accessibilityLabel("返回上级")
        }
    }

    @ViewBuilder
    private var trailingToolbarItem: some View {
        if library.isSelecting {
            HStack(spacing: 16) {
                selectionMenu

                Button("完成") {
                    library.clearSelection()
                }
                .tint(.yellow)
            }
        } else {
            Menu {
                Button {
                    library.revealStorageLocation()
                } label: {
                    Label("打开文件存放位置", systemImage: "folder")
                }

                Divider()

                Button {
                    showCreateFolder = true
                } label: {
                    Label("创建文件夹", systemImage: "folder.badge.plus")
                }

                Button {
                    library.toggleSelectionMode()
                } label: {
                    Label("选择", systemImage: "checkmark.circle")
                }

                Divider()

                Button {
                    library.copySelection()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .disabled(library.selectedCount == 0)

                Button {
                    library.cutSelection()
                } label: {
                    Label("剪切", systemImage: "scissors")
                }
                .disabled(library.selectedCount == 0)

                Button {
                    library.pasteClipboard()
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }
                .disabled(!library.canPaste)

                Button(role: .destructive) {
                    confirmDeleteSelection = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(library.selectedCount == 0)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.semibold))
            }
            .tint(.yellow)
            .accessibilityLabel("更多")
        }
    }

    private var selectionMenu: some View {
        Menu {
            Button {
                library.copySelection()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .disabled(library.selectedCount == 0)

            Button {
                library.cutSelection()
            } label: {
                Label("剪切", systemImage: "scissors")
            }
            .disabled(library.selectedCount == 0)

            Button {
                library.pasteClipboard()
            } label: {
                Label("粘贴", systemImage: "doc.on.clipboard")
            }
            .disabled(!library.canPaste)

            Button(role: .destructive) {
                confirmDeleteSelection = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(library.selectedCount == 0)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3.weight(.semibold))
        }
        .tint(.yellow)
        .accessibilityLabel("更多")
    }

    private func setChromeCompact(_ isCompact: Bool) {
        guard compactChrome != isCompact else { return }
        withAnimation(.snappy(duration: 0.34)) {
            compactChrome = isCompact
        }
    }

    private func handleChromeLinkedScroll(_ offset: CGFloat) {
        guard !library.isSelecting else {
            lastScrollOffset = offset
            accumulatedDragDelta = 0
            return
        }

        guard let lastOffset = lastScrollOffset else {
            lastScrollOffset = offset
            return
        }

        let delta = offset - lastOffset
        lastScrollOffset = offset
        guard abs(delta) > 0.4 else { return }
        handleChromeDelta(delta)
    }

    private func handleChromeDelta(_ delta: CGFloat) {
        guard abs(delta) > 0.35 else { return }
        if delta.sign != accumulatedDragDelta.sign {
            accumulatedDragDelta = delta
        } else {
            accumulatedDragDelta += delta
        }

        if accumulatedDragDelta < -18 {
            setChromeCompact(true)
            resetChromeDragTracking()
        } else if accumulatedDragDelta > 26 {
            setChromeCompact(false)
            resetChromeDragTracking()
        }
    }

    private func resetChromeDragTracking() {
        accumulatedDragDelta = 0
    }

    private func closeOpenDeleteRow() {
        guard openDeleteRowID != nil else { return }
        withAnimation(.snappy(duration: 0.24)) {
            openDeleteRowID = nil
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("这个文件夹是空的")
                .font(.body.weight(.semibold))
            Text(library.breadcrumbs)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
    }

    private func open(_ item: LibraryItem) {
        if openDeleteRowID != nil {
            closeOpenDeleteRow()
            return
        }

        if library.isSelecting {
            library.toggleSelection(item)
            return
        }

        switch item.kind {
        case .folder:
            library.enter(item)
        case .media:
            library.importMedia(from: item.url, player: player)
            player.play()
        case .subtitle, .image, .document, .other:
            previewItem = item
        }
    }
}

private struct FileManagerRow: View {
    private let deleteButtonWidth: CGFloat = 86

    let item: LibraryItem
    let isActive: Bool
    let videoMetadata: VideoMetadata?
    let progress: PlaybackProgressRecord?
    let isSelecting: Bool
    let isSelected: Bool
    let open: () -> Void
    let toggleSelection: () -> Void
    let beginSelection: () -> Void
    @Binding var openDeleteRowID: URL?
    let delete: () -> Void
    @State private var horizontalOffset: CGFloat = 0

    private var isDeleteOpen: Bool {
        openDeleteRowID == item.id
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if !isSelecting {
                Button(role: .destructive) {
                    withAnimation(.snappy(duration: 0.24)) {
                        openDeleteRowID = nil
                    }
                    delete()
                } label: {
                    ZStack {
                        Color.red
                        Image(systemName: "trash")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: deleteButtonWidth)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除")
            }

            rowContent
                .background(Color(.systemBackground))
                .offset(x: isSelecting ? 0 : horizontalOffset)
                .gesture(swipeGesture)
        }
        .clipped()
        .onChange(of: isSelecting) { _, newValue in
            if newValue {
                openDeleteRowID = nil
            }
        }
        .onChange(of: openDeleteRowID) { _, newValue in
            if newValue != item.id {
                withAnimation(.snappy(duration: 0.22)) {
                    horizontalOffset = 0
                }
            }
        }
        .onAppear {
            horizontalOffset = isDeleteOpen ? -deleteButtonWidth : 0
            VideoMetadataStore.shared.loadIfNeeded(for: item.url)
        }
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 76)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            icon

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.yellow : Color.primary)
                    .lineLimit(1)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let progress, item.kind == .media, progress.progress > 0, !progress.completed {
                    ProgressView(value: progress.progress)
                        .tint(.yellow)
                        .frame(height: 3)
                }
            }

            Spacer()

            trailingContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 70)
        .contentShape(Rectangle())
        .onTapGesture {
            if openDeleteRowID != nil {
                withAnimation(.snappy(duration: 0.24)) {
                    openDeleteRowID = nil
                }
            } else {
                open()
            }
        }
        .onLongPressGesture(minimumDuration: 0.45, perform: beginSelection)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isSelecting else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.35 else { return }
                if openDeleteRowID != item.id {
                    openDeleteRowID = item.id
                }
                horizontalOffset = min(0, max(-deleteButtonWidth, horizontal))
            }
            .onEnded { value in
                guard !isSelecting else { return }
                let horizontal = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let shouldOpen = horizontal < -deleteButtonWidth * 0.42 || predicted < -deleteButtonWidth
                withAnimation(.snappy(duration: 0.26)) {
                    openDeleteRowID = shouldOpen ? item.id : nil
                    horizontalOffset = shouldOpen ? -deleteButtonWidth : 0
                }
            }
    }

    @ViewBuilder
    private var trailingContent: some View {
        if isSelecting {
            Button(action: toggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.yellow : Color.secondary)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "取消选择" : "选择")
        } else {
            if item.kind == .folder {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.yellow)
            }
        }
    }

    private var icon: some View {
        ZStack {
            if item.kind == .folder {
                Image(systemName: "folder")
                    .font(.system(size: 38, weight: .light))
            } else if videoMetadata?.thumbnailURL != nil,
                      let image = VideoMetadataStore.shared.cachedThumbnail(for: item.url) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 58, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "play.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.48), in: Circle())
                            .padding(4)
                    }
            } else {
                Circle()
                    .fill(iconColor.opacity(0.12))
                Image(systemName: iconName)
                    .font(.body.weight(.semibold))
            }
        }
        .foregroundStyle(iconColor)
        .frame(width: 58, height: 46)
    }

    private var iconName: String {
        switch item.kind {
        case .folder:
            "folder"
        case .media:
            MediaLibrary.isVideoExtension(item.fileExtension) ? "film.fill" : "waveform"
        case .subtitle:
            "captions.bubble"
        case .image:
            "photo"
        case .document:
            "doc.text"
        case .other:
            "doc"
        }
    }

    private var iconColor: Color {
        switch item.kind {
        case .folder:
            .yellow
        case .media:
            .yellow
        case .subtitle:
            .blue
        case .image:
            .green
        case .document:
            .purple
        case .other:
            .secondary
        }
    }

    private var detailText: String {
        switch item.kind {
        case .folder:
            return "\(item.childCount ?? 0) 个项目"
        case .media, .subtitle, .image, .document, .other:
            let size = ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
            let ext = item.fileExtension.isEmpty ? "文件" : item.fileExtension
            let duration = videoMetadata?.duration.map { "\(formatTime($0)) " } ?? ""
            return "\(duration)\(ext) \(size) \(dateText)"
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: item.modifiedAt)
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
