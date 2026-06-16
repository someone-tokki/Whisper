import Foundation
import UniformTypeIdentifiers

enum MediaLibrary {
    static let audioExtensions = Set(["mp3", "m4a", "wav", "aiff", "aif", "flac", "aac", "ogg"])
    static let videoExtensions = Set(["mp4", "m4v", "mov"])
    static let mediaExtensions = audioExtensions.union(videoExtensions)
    static let subtitleExtensions = Set(["srt", "vtt", "lrc", "ass", "ssa", "txt"])
    static let imageExtensions = Set(["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp"])
    static let documentExtensions = Set(["pdf", "doc", "docx", "rtf", "md", "markdown", "epub"])

    static let mediaTypes: [UTType] = [
        .audio,
        .movie,
        .mpeg4Movie,
        .quickTimeMovie,
        .mp3,
        .wav,
        UTType(filenameExtension: "m4a") ?? .audio,
        UTType(filenameExtension: "flac") ?? .audio,
        UTType(filenameExtension: "aac") ?? .audio,
        UTType(filenameExtension: "ogg") ?? .audio
    ]

    static let subtitleTypes: [UTType] = [
        .plainText,
        .utf8PlainText,
        UTType(filenameExtension: "srt") ?? .plainText,
        UTType(filenameExtension: "vtt") ?? .plainText,
        UTType(filenameExtension: "lrc") ?? .plainText,
        UTType(filenameExtension: "ass") ?? .plainText,
        UTType(filenameExtension: "ssa") ?? .plainText
    ]

    static func displayName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    static func isVideo(_ url: URL) -> Bool {
        videoExtensions.contains(url.pathExtension.lowercased())
    }

    static func isVideoExtension(_ fileExtension: String) -> Bool {
        videoExtensions.contains(fileExtension.lowercased())
    }

    static func secureRead<T>(from url: URL, operation: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}
