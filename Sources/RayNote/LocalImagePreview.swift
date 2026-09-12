import AppKit
import ImageIO

struct LiveImagePreview {
    let range: NSRange
    let url: URL
    let size: NSSize
    let cacheKey: NSString
}

/// Read dimensions without decoding the full image. Only visible previews are
/// decoded, as bounded thumbnails, so a note can contain many large originals.
@MainActor final class LocalImagePreviewCache {
    private let images = NSCache<NSString, NSImage>()
    init() { images.totalCostLimit = 32 * 1024 * 1024 }

    func preview(range: NSRange, destination: String, directory: URL, width: CGFloat) -> LiveImagePreview? {
        guard let url = MarkdownAssets.resolve(destination, relativeTo: directory), url.isFileURL,
              let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        var w = CGFloat(pixelWidth.doubleValue), h = CGFloat(pixelHeight.doubleValue)
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) { swap(&w, &h) }
        guard w > 0, h > 0, width > 0 else { return nil }
        let scale = min(1, width / w, 400 / h)
        let key = "\(url.absoluteString)|\(attributes.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(attributes.fileSize ?? 0)" as NSString
        return LiveImagePreview(range: range, url: url, size: NSSize(width: w * scale, height: h * scale), cacheKey: key)
    }
    func image(for preview: LiveImagePreview) -> NSImage? {
        if let cached = images.object(forKey: preview.cacheKey) { return cached }
        guard let source = CGImageSourceCreateWithURL(preview.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { return nil }
        let result = NSImage(cgImage: image, size: preview.size)
        images.setObject(result, forKey: preview.cacheKey, cost: image.bytesPerRow * image.height)
        return result
    }
}
