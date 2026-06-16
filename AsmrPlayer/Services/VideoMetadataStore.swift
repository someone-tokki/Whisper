import AVFoundation
import CryptoKit
import Foundation
import UIKit

struct VideoMetadata: Equatable {
    var duration: TimeInterval?
    var thumbnailURL: URL?
}

@MainActor
final class VideoMetadataStore: ObservableObject {
    static let shared = VideoMetadataStore()

    @Published private(set) var cache: [URL: VideoMetadata] = [:]

    private let fileManager = FileManager.default
    private let thumbnailDirectory: URL
    private var loading: Set<URL> = []
    private let imageCache = NSCache<NSURL, UIImage>()

    private init() {
        thumbnailDirectory = AppStorageLocation.videoThumbnailDirectory
    }

    func metadata(for url: URL) -> VideoMetadata? {
        cache[url]
    }

    func loadIfNeeded(for url: URL) {
        guard MediaLibrary.isVideo(url), cache[url] == nil, !loading.contains(url) else { return }
        loading.insert(url)
        Task {
            let metadata = await generateMetadata(for: url)
            await MainActor.run {
                self.cache[url] = metadata
                self.loading.remove(url)
            }
        }
    }

    func remove(for url: URL) {
        cache.removeValue(forKey: url)
        let thumb = thumbnailURL(for: url)
        imageCache.removeObject(forKey: thumb as NSURL)
        try? fileManager.removeItem(at: thumb)
    }

    func cachedThumbnail(for url: URL) -> UIImage? {
        guard let thumbnailURL = cache[url]?.thumbnailURL else { return nil }
        if let cached = imageCache.object(forKey: thumbnailURL as NSURL) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: thumbnailURL.path) else { return nil }
        imageCache.setObject(image, forKey: thumbnailURL as NSURL)
        return image
    }

    private func generateMetadata(for url: URL) async -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration).seconds
        let thumbnailURL = await generateThumbnail(for: asset, sourceURL: url)
        return VideoMetadata(
            duration: duration?.isFinite == true ? duration : nil,
            thumbnailURL: thumbnailURL
        )
    }

    private func generateThumbnail(for asset: AVURLAsset, sourceURL: URL) async -> URL? {
        let destination = thumbnailURL(for: sourceURL)
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 420, height: 260)

        do {
            let image = try generator.copyCGImage(at: CMTime(seconds: 0.4, preferredTimescale: 600), actualTime: nil)
            let uiImage = UIImage(cgImage: image)
            guard let data = uiImage.jpegData(compressionQuality: 0.74) else { return nil }
            try AppStorageLocation.ensureDirectory(thumbnailDirectory)
            try data.write(to: destination, options: .atomic)
            imageCache.setObject(uiImage, forKey: destination as NSURL)
            return destination
        } catch {
            return nil
        }
    }

    private func thumbnailURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return thumbnailDirectory.appendingPathComponent("\(digest).jpg")
    }
}
