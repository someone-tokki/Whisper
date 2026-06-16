import Foundation

struct SubtitleCue: Identifiable, Equatable {
    let id = UUID()
    let index: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    func contains(_ time: TimeInterval) -> Bool {
        start <= time && time < end
    }
}
