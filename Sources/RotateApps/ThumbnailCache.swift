import AppKit

/// Window thumbnails, captured off the main thread and kept between switcher sessions.
///
/// Capturing goes through the WindowServer and is the single most expensive thing the switcher
/// does. Requests are therefore serialised onto a small worker pool, taken at nominal resolution,
/// and scaled down before they reach the main thread. A cached image is shown immediately and
/// silently replaced once a fresh capture lands.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    /// Longest edge, in pixels, of a stored thumbnail. Plenty for the largest switcher item on a
    /// Retina display while keeping every capture cheap to hold and draw.
    static let maxPixelSize: CGFloat = 480

    private struct Entry {
        let image: NSImage
        let capturedAt: Date
    }

    private let lock = NSLock()
    private var entries: [CGWindowID: Entry] = [:]
    private var inFlight: [CGWindowID: [(NSImage) -> Void]] = [:]
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "RotateApps.thumbnails"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    func cachedImage(for windowID: CGWindowID) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return entries[windowID]?.image
    }

    /// Captures `windowID` unless a thumbnail newer than `maxAge` is already stored. `completion`
    /// runs on the main thread only when a new capture succeeded.
    func refresh(windowID: CGWindowID, maxAge: TimeInterval, completion: ((NSImage) -> Void)? = nil) {
        lock.lock()
        if let entry = entries[windowID], Date().timeIntervalSince(entry.capturedAt) < maxAge {
            lock.unlock()
            return
        }
        if var waiting = inFlight[windowID] {
            if let completion { waiting.append(completion) }
            inFlight[windowID] = waiting
            lock.unlock()
            return
        }
        inFlight[windowID] = completion.map { [$0] } ?? []
        lock.unlock()

        queue.addOperation { [weak self] in
            guard let self else { return }
            let image = Self.capture(windowID: windowID)

            self.lock.lock()
            let waiting = self.inFlight.removeValue(forKey: windowID) ?? []
            if let image {
                self.entries[windowID] = Entry(image: image, capturedAt: Date())
            }
            self.lock.unlock()

            guard let image, !waiting.isEmpty else { return }
            DispatchQueue.main.async {
                waiting.forEach { $0(image) }
            }
        }
    }

    /// Pre-captures windows that have no usable thumbnail yet, and forgets closed windows.
    func warmUp(windowIDs: [CGWindowID], maxAge: TimeInterval) {
        let live = Set(windowIDs)
        lock.lock()
        entries = entries.filter { live.contains($0.key) }
        lock.unlock()

        for windowID in windowIDs {
            refresh(windowID: windowID, maxAge: maxAge)
        }
    }

    private static func capture(windowID: CGWindowID) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            .null,
            [.optionIncludingWindow],
            windowID,
            [.nominalResolution, .boundsIgnoreFraming]
        ) else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }

        let scale = min(1, maxPixelSize / max(width, height))
        let targetSize = CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
        guard scale < 1, let scaled = downscale(cgImage, to: targetSize) else {
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }
        return NSImage(cgImage: scaled, size: NSSize(width: targetSize.width, height: targetSize.height))
    }

    private static func downscale(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
