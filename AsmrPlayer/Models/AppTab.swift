import SwiftUI

enum AppTab: CaseIterable, Identifiable {
    case library
    case playlist
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .library:
            "资料库"
        case .playlist:
            "播放列表"
        case .settings:
            "设置"
        }
    }

    var iconName: String {
        switch self {
        case .library:
            "square.grid.2x2.fill"
        case .playlist:
            "play.square.stack.fill"
        case .settings:
            "gearshape.fill"
        }
    }
}
