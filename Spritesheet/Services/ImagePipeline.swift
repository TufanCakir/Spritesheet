//
//  ImagePipeline.swift
//  Spritesheet
//
//  Created by Tufan Cakir on 13.10.26.
//

import CoreGraphics
import Foundation
import ImageIO

actor ImagePipeline {
    static let shared = ImagePipeline()
    private let storage = ProjectStorage()
    private let cache = NSCache<NSString, CGImageBox>()
    private var currentSourceURL: URL?
    private var currentSourceImage: CGImage?

    func thumbnail(
        projectID: UUID,
        source: SpriteSource,
        frame: SpriteFrame,
        maxPixelSize: Int = 240
    ) throws -> CGImage {
        let key =
            "\(source.id.uuidString)-\(frame.pixelRect.x)-\(frame.pixelRect.y)-\(frame.pixelRect.width)-\(frame.pixelRect.height)-\(maxPixelSize)"
            as NSString
        if let cached = cache.object(forKey: key) {
            return cached.image
        }

        let url = try storage.sourceURL(
            projectID: projectID,
            relativePath: source.relativePath
        )
        if currentSourceURL != url {
            currentSourceImage = nil
            currentSourceImage = try PNGFrameCodec.load(url)
            currentSourceURL = url
        }
        guard let image = currentSourceImage else {
            throw ImportFailure.corrupt(source.originalFilename)
        }
        let crop = try FrameExtractor.crop(image, rect: frame.pixelRect)
        cache.setObject(
            CGImageBox(image: crop),
            forKey: key,
            cost: crop.bytesPerRow * crop.height
        )
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
