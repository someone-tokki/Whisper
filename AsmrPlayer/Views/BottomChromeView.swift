import SwiftUI

struct BottomChromeView: View {
    @Binding var selectedTab: AppTab
    let isCompact: Bool
    let showsMiniPlayer: Bool
    let activeCompactTab: AppTab?
    let expandChrome: () -> Void
    let expandPlayer: () -> Void
    let openSearch: () -> Void
    @Namespace private var chromeNamespace

    private var chromeMode: ChromeMode {
        if !showsMiniPlayer {
            return .tabsOnly
        }
        return isCompact ? .compact : .expanded
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            switch chromeMode {
            case .tabsOnly:
                tabOnlyChrome
            case .compact:
                compactChrome
            case .expanded:
                expandedChrome
            }
        }
        .animation(chromeAnimation, value: chromeMode)
        .animation(chromeAnimation, value: selectedTab)
    }

    private var expandedChrome: some View {
        VStack(spacing: 9) {
            MiniPlayerView(style: .wide, expand: expandPlayer)
                .matchedGeometryEffect(
                    id: ChromeGeometryID.miniPlayer,
                    in: chromeNamespace,
                    properties: .frame,
                    anchor: .center
                )
                .reportMiniPlayerFrame()

            HStack(spacing: 12) {
                tabBar
                searchButton
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .bottom)))
    }

    private var tabOnlyChrome: some View {
        HStack(spacing: 12) {
            tabBar
            searchButton
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .bottom)))
    }

    private var compactChrome: some View {
        HStack(spacing: 10) {
            compactCurrentTab

            MiniPlayerView(style: .compact, expand: expandPlayer)
                .matchedGeometryEffect(
                    id: ChromeGeometryID.miniPlayer,
                    in: chromeNamespace,
                    properties: .frame,
                    anchor: .center
                )
                .reportMiniPlayerFrame()
                .layoutPriority(1)

            searchButton
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .bottom)))
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(chromeAnimation) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.iconName)
                            .font(.title3.weight(.semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.red : Color.primary)
                    .frame(width: 94, height: 58)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
    }

    private var compactCurrentTab: some View {
        Button(action: expandChrome) {
            Image(systemName: (activeCompactTab ?? selectedTab).iconName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.red)
                .frame(width: 62, height: 62)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("展开底栏")
    }

    private var searchButton: some View {
        Button(action: openSearch) {
            Image(systemName: "magnifyingglass")
                .font(.title.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 62, height: 62)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("搜索")
    }

    private var chromeAnimation: Animation {
        .interactiveSpring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)
    }
}

private enum ChromeMode: Equatable {
    case tabsOnly
    case compact
    case expanded
}

private enum ChromeGeometryID {
    static let miniPlayer = "bottomChrome.miniPlayer"
}

struct MiniPlayerFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

struct ChromeScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChromeLinkedScrollOffsetReader: View {
    let coordinateSpaceName: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: ChromeScrollOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(coordinateSpaceName)).minY
                )
        }
        .frame(height: 0)
    }
}

private extension View {
    func reportMiniPlayerFrame() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: MiniPlayerFramePreferenceKey.self,
                        value: proxy.frame(in: .global)
                    )
            }
        }
    }
}
