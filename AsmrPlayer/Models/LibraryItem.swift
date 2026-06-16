import Foundation

struct LibraryItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case folder
        case media
        case subtitle
        case image
        case document
        case other
    }

    let id: URL
    let url: URL
    let kind: Kind
    let title: String
    let fileExtension: String
    let fileSize: Int64
    let modifiedAt: Date
    let childCount: Int?

    var isPlayable: Bool {
        kind == .media
    }

    var isLoadableSubtitle: Bool {
        kind == .subtitle
    }
}
