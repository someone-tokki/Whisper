import Foundation

struct Playlist: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var note: String
    var itemPaths: [String]
    var createdAt: Date = .now
    var updatedAt: Date = .now

    var itemCount: Int {
        itemPaths.count
    }
}
