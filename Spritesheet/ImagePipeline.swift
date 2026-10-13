import CoreGraphics
import Foundation
import ImageIO

actor ImagePipeline {
    static let shared = ImagePipeline()
    private let storage = ProjectStorage()
    private let cache = NSCache<NSString, CGImageBox>()

    func thumbnail(projectID: UUID, source: SpriteSource, frame: SpriteFrame, maxPixelSize: Int = 240) throws -> CGImage {
        let key = "\(source.id.uuidString)-\(frame.pixelRect.x)-\(frame.pixelRect.y)-\(frame.pixelRect.width)-\(frame.pixelRect.height)-\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached.image
        }

        let url = try storage.sourceURL(projectID: projectID, relativePath: source.relativePath)
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                imageSource,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            throw ImportFailure.corrupt(source.originalFilename)
        }

        let rect = frame.pixelRect
        let cropRect = CGRect(
            x: rect.x,
            y: image.height - rect.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        guard let crop = image.cropping(to: cropRect) else {
            throw ExportFailure.invalidFrame(source.originalFilename)
        }
        cache.setObject(CGImageBox(image: crop), forKey: key, cost: crop.bytesPerRow * crop.height)
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return crop
    }
}

private final class CGImageBox {
    let image: CGImage

    init(image: CGImage) {
        self.image = image
    }
}
