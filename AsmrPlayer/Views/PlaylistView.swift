import SwiftUI

struct PlaylistView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var playlistStore: PlaylistStore
    @Binding var compactChrome: Bool

    @State private var selectedPlaylistID: UUID?
    @State private var isSelectingPlaylists = false
    @State private var selectedPlaylistIDs = Set<UUID>()
    @State private var isSelectingMedia = false
    @State private var selectedMediaPaths = Set<String>()
    @State private var selectedAddMediaPaths = Set<String>()
    @State private var reorderedMediaPaths: [String] = []
    @State private var draggingMediaPath: String?
    @State private var draggingMediaTranslation: CGFloat = 0
    @State private var dragStartIndex = 0
    @State private var showCreatePlaylist = false
    @State private var showEditPlaylist = false
    @State private var showAddMedia = false
    @State private var showDeletePlaylists = false
    @State private var showDeleteMedia = false
    @State private var draftName = ""
    @State private var draftNote = ""
    @State private var lastScrollOffset: CGFloat?
    @State private var accumulatedScrollDelta: CGFloat = 0
    @State private var lastDragTranslation: CGFloat = 0
    @State private var accumulatedDragDelta: CGFloat = 0
    private let scrollCoordinateSpaceName = "playlist-scroll"

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        ChromeLinkedScrollOffsetReader(coordinateSpaceName: scrollCoordinateSpaceName)

                        if let playlist = currentPlaylist {
                            detailContent(for: playlist)
                        } else {
                            listContent
                        }
                    }
                    .padding(.bottom, compactChrome ? 112 : 178)
                }
                .coordinateSpace(name: scrollCoordinateSpaceName)
                .onPreferenceChange(ChromeScrollOffsetPreferenceKey.self, perform: handleChromeLinkedScroll)
                .simultaneousGesture(chromeLinkedDragGesture)
                .background(Color(.systemBackground))
                .navigationTitle(currentPlaylist?.name ?? "播放列表")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        leadingToolbar
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        trailingToolbar
                    }
                }
            }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistEditorSheet(
                    title: "创建播放列表",
                    name: $draftName,
                    note: $draftNote,
                    cancel: resetDrafts,
                    confirm: createPlaylist
                )
            }
            .sheet(isPresented: $showEditPlaylist) {
                PlaylistEditorSheet(
                    title: "编辑播放列表",
                    name: $draftName,
                    note: $draftNote,
                    cancel: resetDrafts,
                    confirm: updatePlaylist
                )
            }
            .sheet(isPresented: $showAddMedia) {
                if let playlist = currentPlaylist {
                    AddMediaSheet(
                        playlist: playlist,
                        library: library,
                        selectedPaths: $selectedAddMediaPaths
                    ) {
                        let urls = selectedAddMediaPaths.map(URL.init(fileURLWithPath:))
                        playlistStore.addMedia(to: playlist.id, urls: urls)
                        selectedAddMediaPaths.removeAll()
                        showAddMedia = false
                    }
                }
            }
            .confirmationDialog("删除播放列表？", isPresented: $showDeletePlaylists, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let playlist = currentPlaylist {
                        playlistStore.deletePlaylist(id: playlist.id)
                        selectedPlaylistID = nil
                    } else {
                        playlistStore.deletePlaylists(ids: Array(selectedPlaylistIDs))
                        selectedPlaylistIDs.removeAll()
                        isSelectingPlaylists = false
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只会删除播放列表索引，不会删除资料库里的媒体文件。")
            }
            .confirmationDialog("从播放列表移除？", isPresented: $showDeleteMedia, titleVisibility: .visible) {
                Button("移除", role: .destructive) {
                    guard let playlist = currentPlaylist else { return }
                    playlistStore.removeMedia(from: playlist.id, paths: selectedMediaPaths)
                    selectedMediaPaths.removeAll()
                    isSelectingMedia = false
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只会从这个播放列表移除索引，不会删除资料库里的媒体文件。")
            }
            .onChange(of: selectedPlaylistID) { _, _ in
                resetMediaEditingState()
            }
            .edgeBackGesture(isEnabled: canEdgeBack) {
                handleEdgeBack()
            }
        }
    }

    private var canEdgeBack: Bool {
        currentPlaylist != nil && !isSelectingPlaylists && !isSelectingMedia && draggingMediaPath == nil
    }

    private func handleEdgeBack() {
        guard currentPlaylist != nil else { return }
        selectedPlaylistID = nil
        resetMediaEditingState()
    }

    @ViewBuilder
    private var leadingToolbar: some View {
        if currentPlaylist != nil {
            Button {
                selectedPlaylistID = nil
                isSelectingMedia = false
                selectedMediaPaths.removeAll()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tint(.yellow)
            .accessibilityLabel("返回播放列表")
        } else if isSelectingPlaylists {
            Button(allPlaylistsSelected ? "取消全选" : "全选") {
                if allPlaylistsSelected {
                    selectedPlaylistIDs.removeAll()
                } else {
                    selectedPlaylistIDs = Set(playlistStore.playlists.map(\.id))
                }
            }
            .tint(.yellow)
        }
    }

    @ViewBuilder
    private var trailingToolbar: some View {
        if let playlist = currentPlaylist {
            if isSelectingMedia {
                HStack(spacing: 16) {
                    detailMenu(for: playlist)
                    Button("完成") {
                        finishMediaSelection()
                    }
                    .tint(.yellow)
                }
            } else {
                detailMenu(for: playlist)
            }
        } else if isSelectingPlaylists {
            HStack(spacing: 16) {
                listMenu
                Button("完成") {
                    isSelectingPlaylists = false
                    selectedPlaylistIDs.removeAll()
                }
                .tint(.yellow)
            }
        } else {
            listMenu
        }
    }

    private var listMenu: some View {
        Menu {
            Button {
                draftName = ""
                draftNote = ""
                showCreatePlaylist = true
            } label: {
                Label("创建播放列表", systemImage: "plus.square.on.square")
            }

            Button {
                isSelectingPlaylists = true
            } label: {
                Label("选择", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                showDeletePlaylists = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(selectedPlaylistIDs.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3.weight(.semibold))
        }
        .tint(.yellow)
        .accessibilityLabel("更多")
    }

    private func detailMenu(for playlist: Playlist) -> some View {
        Menu {
            Button {
                selectedAddMediaPaths.removeAll()
                showAddMedia = true
            } label: {
                Label("添加", systemImage: "plus.circle")
            }

            Button {
                draftName = playlist.name
                draftNote = playlist.note
                showEditPlaylist = true
            } label: {
                Label("编辑", systemImage: "pencil")
            }

            Button {
                beginMediaSelection(in: playlist)
            } label: {
                Label("选择", systemImage: "checkmark.circle")
            }

            Divider()

            Button {
                pasteCopiedMedia(into: playlist)
            } label: {
                Label("粘贴", systemImage: "doc.on.clipboard")
            }
            .disabled(library.copiedMediaURLs.isEmpty)

            Button(role: .destructive) {
                showDeleteMedia = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(selectedMediaPaths.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3.weight(.semibold))
        }
        .tint(.yellow)
        .accessibilityLabel("更多")
    }

    private var listContent: some View {
        LazyVStack(spacing: 0) {
            if playlistStore.playlists.isEmpty {
                emptyList
                    .padding(.top, 40)
            } else {
                ForEach(playlistStore.playlists) { playlist in
                    PlaylistSummaryRow(
                        playlist: playlist,
                        isSelecting: isSelectingPlaylists,
                        isSelected: selectedPlaylistIDs.contains(playlist.id),
                        open: {
                            if isSelectingPlaylists {
                                togglePlaylistSelection(playlist.id)
                            } else {
                                selectedPlaylistID = playlist.id
                            }
                        },
                        toggleSelection: {
                            togglePlaylistSelection(playlist.id)
                        },
                        beginSelection: {
                            beginPlaylistSelection(with: playlist.id)
                        },
                        delete: {
                            playlistStore.deletePlaylist(id: playlist.id)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func detailContent(for playlist: Playlist) -> some View {
        let mediaPaths = displayedMediaPaths(for: playlist)
        LazyVStack(spacing: 0) {
            PlaylistDetailHeader(playlist: playlist)

            if mediaPaths.isEmpty {
                emptyDetail
                    .padding(.top, 40)
            } else {
                let rows = indexedMediaPaths(mediaPaths)

                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            mediaItemRow(
                                for: row.path,
                                index: row.index,
                                playlist: playlist,
                                totalCount: mediaPaths.count
                            )
                        }
                    }
                    .zIndex(0)

                    if let draggingPath = draggingMediaPath {
                        draggingMediaOverlay(for: draggingPath)
                    }
                }
                .zIndex(1)
            }
        }
        .animation(.snappy(duration: 0.24), value: mediaPaths)
        .onChange(of: isSelectingMedia) { _, newValue in
            if newValue {
                syncReorderState(with: playlist)
            } else {
                resetMediaEditingState()
            }
        }
        .onChange(of: playlist.itemPaths) { _, newValue in
            guard isSelectingMedia else { return }
            reorderedMediaPaths = newValue
        }
    }

    private var currentPlaylist: Playlist? {
        guard let selectedPlaylistID else { return nil }
        return playlistStore.playlist(id: selectedPlaylistID)
    }

    private var allPlaylistsSelected: Bool {
        !playlistStore.playlists.isEmpty && selectedPlaylistIDs.count == playlistStore.playlists.count
    }

    private func setChromeCompact(_ isCompact: Bool) {
        guard compactChrome != isCompact else { return }
        withAnimation(.snappy(duration: 0.34)) {
            compactChrome = isCompact
        }
    }

    private var chromeLinkedDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isSelectingMedia, draggingMediaPath == nil else { return }
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard vertical > horizontal * 1.2 else { return }

                let delta = value.translation.height - lastDragTranslation
                lastDragTranslation = value.translation.height
                handleChromeDelta(delta)
            }
            .onEnded { value in
                guard !isSelectingMedia, draggingMediaPath == nil else {
                    resetChromeDragTracking()
                    return
                }
                let vertical = value.translation.height
                let horizontal = value.translation.width
                let predictedVertical = value.predictedEndTranslation.height
                if abs(vertical) > abs(horizontal) * 1.2 {
                    if vertical < -18 || predictedVertical < -42 {
                        setChromeCompact(true)
                    } else if vertical > 24 || predictedVertical > 54 {
                        setChromeCompact(false)
                    }
                }
                resetChromeDragTracking()
            }
    }

    private func handleChromeLinkedScroll(_ offset: CGFloat) {
        guard !isSelectingMedia, draggingMediaPath == nil else {
            lastScrollOffset = offset
            accumulatedScrollDelta = 0
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
            resetChromeDragTracking(keepLastTranslation: true)
        } else if accumulatedDragDelta > 26 {
            setChromeCompact(false)
            resetChromeDragTracking(keepLastTranslation: true)
        }
    }

    private func resetChromeDragTracking(keepLastTranslation: Bool = false) {
        if !keepLastTranslation {
            lastDragTranslation = 0
        }
        accumulatedDragDelta = 0
        accumulatedScrollDelta = 0
    }

    private func createPlaylist() {
        if let playlist = playlistStore.createPlaylist(name: draftName, note: draftNote) {
            selectedPlaylistID = playlist.id
        }
        resetDrafts()
    }

    private func updatePlaylist() {
        guard let playlist = currentPlaylist else { return }
        playlistStore.updatePlaylist(id: playlist.id, name: draftName, note: draftNote)
        resetDrafts()
    }

    private func resetDrafts() {
        draftName = ""
        draftNote = ""
        showCreatePlaylist = false
        showEditPlaylist = false
    }

    private func beginMediaSelection(in playlist: Playlist) {
        syncReorderState(with: playlist)
        isSelectingMedia = true
    }

    private func finishMediaSelection() {
        isSelectingMedia = false
        selectedMediaPaths.removeAll()
        resetMediaEditingState()
    }

    private func syncReorderState(with playlist: Playlist) {
        reorderedMediaPaths = playlist.itemPaths
        draggingMediaPath = nil
        draggingMediaTranslation = 0
        dragStartIndex = 0
    }

    private func resetMediaEditingState() {
        reorderedMediaPaths.removeAll()
        draggingMediaPath = nil
        draggingMediaTranslation = 0
        dragStartIndex = 0
    }

    private func displayedMediaPaths(for playlist: Playlist) -> [String] {
        if isSelectingMedia, !reorderedMediaPaths.isEmpty {
            return reorderedMediaPaths
        }
        return playlist.itemPaths
    }

    private func togglePlaylistSelection(_ id: UUID) {
        if selectedPlaylistIDs.contains(id) {
            selectedPlaylistIDs.remove(id)
        } else {
            selectedPlaylistIDs.insert(id)
        }
    }

    private func beginPlaylistSelection(with id: UUID) {
        isSelectingPlaylists = true
        selectedPlaylistIDs = [id]
    }

    private func toggleMediaSelection(_ path: String) {
        if selectedMediaPaths.contains(path) {
            selectedMediaPaths.remove(path)
        } else {
            selectedMediaPaths.insert(path)
        }
    }

    private func pasteCopiedMedia(into playlist: Playlist) {
        let urls = library.copiedMediaURLs
        guard !urls.isEmpty else { return }
        playlistStore.insertMedia(into: playlist.id, urls: urls)
    }

    private func commitMediaReorder(in playlist: Playlist, finalTranslation: CGFloat) {
        guard isSelectingMedia, let draggingPath = draggingMediaPath, !reorderedMediaPaths.isEmpty else { return }
        var paths = reorderedMediaPaths
        guard let sourceIndex = paths.firstIndex(of: draggingPath) else {
            draggingMediaPath = nil
            draggingMediaTranslation = 0
            return
        }
        let item = paths.remove(at: sourceIndex)
        let insertionIndex = dragInsertionIndex(totalCount: playlist.itemPaths.count, translation: finalTranslation)
        let destination = min(max(insertionIndex, 0), paths.count)
        paths.insert(item, at: destination)
        let urls = paths.map(URL.init(fileURLWithPath:))
        playlistStore.replaceMedia(in: playlist.id, with: urls)
        reorderedMediaPaths = paths
        draggingMediaPath = nil
        draggingMediaTranslation = 0
    }

    private func dragInsertionIndex(totalCount: Int, translation: CGFloat) -> Int {
        let visibleCount = max(totalCount - 1, 0)
        let rawStep = translation / PlaylistItemRow.rowHeight
        let step: Int
        if rawStep >= 0 {
            step = Int(floor(rawStep + 0.35))
        } else {
            step = Int(ceil(rawStep - 0.35))
        }
        return min(max(dragStartIndex + step, 0), visibleCount)
    }

    private func indexedMediaPaths(_ paths: [String]) -> [IndexedPlaylistItem] {
        paths.enumerated().map { index, path in
            IndexedPlaylistItem(index: index, path: path)
        }
    }

    private func mediaItemRow(for path: String, index: Int, playlist: Playlist, totalCount: Int) -> some View {
        let url = URL(fileURLWithPath: path)
        return PlaylistItemRow(
            url: url,
            index: index,
            isActive: isActive(url),
            isSelecting: isSelectingMedia,
            isSelected: selectedMediaPaths.contains(path),
            open: {
                if isSelectingMedia {
                    toggleMediaSelection(path)
                } else {
                    open(url, in: playlist)
                }
            },
            toggleSelection: {
                toggleMediaSelection(path)
            },
            remove: {
                playlistStore.removeMedia(from: playlist.id, paths: [path])
            },
            dragState: MediaDragState(
                draggingPath: $draggingMediaPath,
                translation: $draggingMediaTranslation,
                startIndex: $dragStartIndex
            ),
            commitReorder: { finalTranslation in
                commitMediaReorder(in: playlist, finalTranslation: finalTranslation)
            }
        )
        .opacity(draggingMediaPath == path ? 0.01 : 1)
        .offset(y: dragOffset(for: path, at: index, totalCount: totalCount))
        .animation(.snappy(duration: 0.18), value: dragTargetIndex(totalCount: totalCount))
        .zIndex(draggingMediaPath == path ? 1_000 : 0)
    }

    private func dragTargetIndex(totalCount: Int) -> Int {
        dragInsertionIndex(totalCount: totalCount, translation: draggingMediaTranslation)
    }

    private func dragOffset(for path: String, at index: Int, totalCount: Int) -> CGFloat {
        guard let draggingPath = draggingMediaPath, draggingPath != path else { return 0 }
        let targetIndex = dragTargetIndex(totalCount: totalCount)

        if targetIndex > dragStartIndex, index > dragStartIndex, index <= targetIndex {
            return -PlaylistItemRow.rowHeight
        }

        if targetIndex < dragStartIndex, index >= targetIndex, index < dragStartIndex {
            return PlaylistItemRow.rowHeight
        }

        return 0
    }

    @ViewBuilder
    private func draggingMediaOverlay(for path: String) -> some View {
        mediaDragOverlayRow(for: path)
            .allowsHitTesting(false)
            .zIndex(10_000)
    }

    private func mediaDragOverlayRow(for path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        return PlaylistItemRow(
            url: url,
            index: dragStartIndex,
            isActive: isActive(url),
            isSelecting: true,
            isSelected: selectedMediaPaths.contains(path),
            open: {},
            toggleSelection: {},
            remove: {},
            dragState: MediaDragState(
                draggingPath: $draggingMediaPath,
                translation: $draggingMediaTranslation,
                startIndex: $dragStartIndex
            ),
            commitReorder: { _ in }
        )
        .frame(height: PlaylistItemRow.rowHeight)
        .offset(y: CGFloat(dragStartIndex) * PlaylistItemRow.rowHeight + draggingMediaTranslation)
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
    }

    private func isActive(_ url: URL) -> Bool {
        player.state.sourceURL?.standardizedFileURL.path == url.standardizedFileURL.path
    }

    private func open(_ url: URL, in playlist: Playlist) {
        guard let queue = playlistStore.playbackQueue(for: playlist.id, currentURL: url) else { return }
        library.importPlaylistMedia(from: url, queue: queue, player: player)
        player.play()
    }

    private var emptyList: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.square.stack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("暂无播放列表")
                .font(.body.weight(.semibold))
            Text("从右上角创建一个播放列表")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("这个列表还没有内容")
                .font(.body.weight(.semibold))
            Text("用右上角更多里的“添加”把资料库中的媒体加入这里")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PlaylistSummaryRow: View {
    private let deleteButtonWidth: CGFloat = 86

    let playlist: Playlist
    let isSelecting: Bool
    let isSelected: Bool
    let open: () -> Void
    let toggleSelection: () -> Void
    let beginSelection: () -> Void
    let delete: () -> Void
    @State private var horizontalOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            if !isSelecting {
                Button(role: .destructive) {
                    withAnimation(.snappy(duration: 0.24)) {
                        horizontalOffset = 0
                    }
                    delete()
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: deleteButtonWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除播放列表")
            }

            rowContent
                .background(Color(.systemBackground))
                .offset(x: isSelecting ? 0 : horizontalOffset)
                .gesture(swipeGesture)
        }
        .clipped()
        .onChange(of: isSelecting) { _, newValue in
            if newValue {
                horizontalOffset = 0
            }
        }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 78)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.yellow.opacity(0.18))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "play.square.stack.fill")
                        .foregroundStyle(.yellow)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(playlist.note.isEmpty ? "无备注" : playlist.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelecting {
                Button(action: toggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.yellow : Color.secondary)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
            } else {
                Text("\(playlist.itemCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if horizontalOffset < 0 {
                withAnimation(.snappy(duration: 0.24)) {
                    horizontalOffset = 0
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
                guard abs(horizontal) > abs(vertical) else { return }
                horizontalOffset = min(0, max(-deleteButtonWidth, horizontal))
            }
            .onEnded { value in
                guard !isSelecting else { return }
                let horizontal = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let shouldOpen = horizontal < -deleteButtonWidth * 0.42 || predicted < -deleteButtonWidth
                withAnimation(.snappy(duration: 0.26)) {
                    horizontalOffset = shouldOpen ? -deleteButtonWidth : 0
                }
            }
    }
}

private struct PlaylistDetailHeader: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(playlist.name)
                .font(.title3.weight(.semibold))
            if !playlist.note.isEmpty {
                Text(playlist.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(playlist.itemCount) 个媒体")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct PlaylistItemRow: View {
    static let rowHeight: CGFloat = 64
    private let deleteButtonWidth: CGFloat = 86
    private let reorderThreshold: CGFloat = 56

    let url: URL
    let index: Int
    let isActive: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let open: () -> Void
    let toggleSelection: () -> Void
    let remove: () -> Void
    let dragState: MediaDragState
    let commitReorder: (CGFloat) -> Void
    @State private var horizontalOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            if !isSelecting, horizontalOffset < -0.5 {
                Button(role: .destructive) {
                    withAnimation(.snappy(duration: 0.24)) {
                        horizontalOffset = 0
                    }
                    remove()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.white)
                        .frame(width: deleteButtonWidth, height: Self.rowHeight)
                        .background(Color.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("移除")
            }

            interactionContent
        }
        .onChange(of: isSelecting) { _, newValue in
            if newValue {
                horizontalOffset = 0
                dragState.draggingPath = nil
                dragState.translation = 0
                dragState.startIndex = 0
            }
        }
        .scaleEffect(isDraggedRow ? 1.02 : 1)
        .shadow(color: isDraggedRow ? Color.black.opacity(0.12) : Color.clear, radius: 10, x: 0, y: 4)
        .frame(height: Self.rowHeight)
        .clipped()
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 72)
        }
    }

    @ViewBuilder
    private var interactionContent: some View {
        if isSelecting {
            rowContent
                .background(Color(.systemBackground))
                .offset(x: 0)
                .highPriorityGesture(reorderGesture)
        } else {
            rowContent
                .background(Color(.systemBackground))
                .offset(x: horizontalOffset)
                .gesture(swipeGesture)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.yellow.opacity(0.16) : Color.secondary.opacity(0.12))
                Image(systemName: MediaLibrary.isVideo(url) ? "film.fill" : "waveform")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isActive ? Color.yellow : Color.secondary)
            }
            .frame(width: 48, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(MediaLibrary.displayName(for: url))
                    .font(.body.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.yellow : Color.primary)
                    .lineLimit(1)
                Text(url.pathExtension.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelecting {
                Image(systemName: "line.3.horizontal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 38)

                Button(action: toggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.yellow : Color.secondary)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
            } else {
                Text(String(format: "%02d", index + 1))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                toggleSelection()
            } else if horizontalOffset < 0 {
                withAnimation(.snappy(duration: 0.24)) {
                    horizontalOffset = 0
                }
            } else {
                open()
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isSelecting else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                horizontalOffset = min(0, max(-deleteButtonWidth, horizontal))
            }
            .onEnded { value in
                guard !isSelecting else { return }
                let shouldOpen = value.translation.width < -deleteButtonWidth * 0.42
                    || value.predictedEndTranslation.width < -deleteButtonWidth
                withAnimation(.snappy(duration: 0.26)) {
                    horizontalOffset = shouldOpen ? -deleteButtonWidth : 0
                }
            }
    }

    private var reorderGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.18)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard isSelecting else { return }
                guard case .second(true, let drag?) = value else { return }
                let path = url.standardizedFileURL.path
                if dragState.draggingPath == nil {
                    dragState.draggingPath = path
                    dragState.startIndex = index
                }
                guard dragState.draggingPath == path else { return }
                dragState.translation = drag.translation.height
            }
            .onEnded { _ in
                guard isSelecting else { return }
                guard dragState.draggingPath == url.standardizedFileURL.path else { return }
                let finalTranslation = dragState.translation
                commitReorder(finalTranslation)
                withAnimation(.snappy(duration: 0.24)) {
                    dragState.translation = 0
                    dragState.draggingPath = nil
                }
            }
    }

    private var isDraggedRow: Bool {
        dragState.draggingPath == url.standardizedFileURL.path
    }
}

private struct MediaDragState {
    @Binding var draggingPath: String?
    @Binding var translation: CGFloat
    @Binding var startIndex: Int
}

private struct IndexedPlaylistItem: Identifiable {
    let index: Int
    let path: String

    var id: String { path }
}

private struct PlaylistEditorSheet: View {
    let title: String
    @Binding var name: String
    @Binding var note: String
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", role: .cancel, action: cancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成", action: confirm)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct AddMediaSheet: View {
    let playlist: Playlist
    let library: LibraryViewModel
    @Binding var selectedPaths: Set<String>
    let confirm: () -> Void
    @State private var currentDirectory: URL

    init(
        playlist: Playlist,
        library: LibraryViewModel,
        selectedPaths: Binding<Set<String>>,
        confirm: @escaping () -> Void
    ) {
        self.playlist = playlist
        self.library = library
        self._selectedPaths = selectedPaths
        self.confirm = confirm
        _currentDirectory = State(initialValue: library.rootDirectory)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(library.mediaBrowserItems(in: currentDirectory)) { item in
                        Button {
                            if item.kind == .folder {
                                currentDirectory = item.url
                            } else {
                                toggle(item.url)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.kind == .folder ? "folder" : mediaIcon(for: item.url))
                                    .foregroundStyle(item.kind == .folder ? Color.yellow : Color.secondary)
                                    .frame(width: 30)

                                Text(item.title)
                                    .lineLimit(1)

                                Spacer()

                                if item.kind == .folder {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: selectedPaths.contains(item.url.standardizedFileURL.path) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(selectedPaths.contains(item.url.standardizedFileURL.path) ? Color.yellow : Color.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }
            .navigationTitle("添加到 \(playlist.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if library.canGoBack(from: currentDirectory) {
                        Button {
                            currentDirectory = library.parentDirectory(of: currentDirectory)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成", action: confirm)
                        .fontWeight(.semibold)
                        .disabled(selectedPaths.isEmpty)
                }
            }
        }
    }

    private func toggle(_ url: URL) {
        let key = url.standardizedFileURL.path
        if selectedPaths.contains(key) {
            selectedPaths.remove(key)
        } else {
            selectedPaths.insert(key)
        }
    }

    private func mediaIcon(for url: URL) -> String {
        MediaLibrary.isVideo(url) ? "film.fill" : "waveform"
    }
}
