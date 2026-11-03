//
//  RemoteImages.swift
//  Ketchup
//
//  One pipeline for every photo the app downloads: profile photos, and the
//  photos in chats. Adapted from AurariaGO's RemoteImages, slimmed down.
//  - Decoded images, downsampled to the size they're drawn at, stay in
//    memory, so a row scrolling back draws on its first frame.
//  - The original bytes stay on disk (Caches/photos), keyed by bucket and
//    path. Every upload gets a new path, so a file never goes stale and each
//    phone downloads each photo once. A private photo is signed only when
//    it isn't on disk yet.
//  - One download per photo however many rows ask, in its own task, so a
//    row that scrolls away doesn't cancel it. Two retries on a network error
//    or a 5xx; a photo that failed isn't asked for again for 20 seconds, and
//    one still on screen asks again after that.
//  - ImageIO decodes off the main thread, at the drawn size.
//  - The disk copy is trimmed past 150 MB, least recently used first, and
//    emptied on sign-out.
//

import SwiftUI
import ImageIO

// MARK: - The view

/// A photo from Storage through the shared cache. `pixels` is the long side
/// to decode at (`RemoteImages.pixels(points:scale:)`), 0 for full size.
/// `content` draws the photo; `placeholder` stands in while it loads, and
/// gets `true` once it couldn't.
struct RemoteImage<Content: View, Placeholder: View>: View {
    let object: StorageObject?
    let pixels: Int
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: (_ failed: Bool) -> Placeholder

    /// What this view loaded, with its key, so a reused view (your own new
    /// photo) never shows the old one.
    @State private var loaded: (key: String, image: UIImage)?
    @State private var failedKey: String?

    var body: some View {
        let key = object.map { RemoteImages.memoryKey($0, pixels: pixels) }
        // Memory first, synchronously: a cached photo draws on the first frame.
        let image: UIImage? = key.flatMap { key in
            if let loaded, loaded.key == key { return loaded.image }
            return RemoteImages.shared.cached(key)
        }
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder(key != nil && failedKey == key)
            }
        }
        .task(id: key) {
            guard let object, let key, RemoteImages.shared.cached(key) == nil else { return }
            // A photo that couldn't load (offline, say) tries again while it's
            // on screen, each time after the pipeline's 20 s pause; 8 tries.
            for _ in 0..<8 where !Task.isCancelled {
                if let image = await RemoteImages.shared.image(object, pixels: pixels) {
                    loaded = (key, image)
                    failedKey = nil
                    return
                }
                failedKey = key
                try? await Task.sleep(for: .seconds(21))
            }
        }
    }
}

// MARK: - The pipeline

/// Memory and disk cache plus loader. Thread-safe; call it from anywhere.
nonisolated final class RemoteImages: @unchecked Sendable {

    static let shared = RemoteImages()

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    /// Past this many bytes on disk, trim down to `trimTo`.
    private let diskLimit = 150 * 1024 * 1024
    private let trimTo = 110 * 1024 * 1024

    private let lock = NSLock()
    /// One download (or disk read) per photo, by storage key.
    private var fetches: [String: Task<Data?, Never>] = [:]
    /// One decode per photo and size, by memory key.
    private var decodes: [String: Task<UIImage?, Never>] = [:]
    /// Photos whose last fetch failed, retried after `backoff`.
    private var failedAt: [String: Date] = [:]
    private let backoff: TimeInterval = 20
    private var writtenSinceTrim = 0

    private let session: URLSession

    #if DEBUG
    /// Offline preview mode (`-screen`): photos come from Debug/PreviewPhotos.swift.
    private static let previewing = UserDefaults.standard.string(forKey: "screen") != nil
    #endif

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folder = caches.appending(path: "photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        memory.totalCostLimit = 80 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = nil  // the folder is the cache
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        Task.detached(priority: .background) { [self] in trim() }
    }

    // MARK: Keys and sizes

    static func memoryKey(_ object: StorageObject, pixels: Int) -> String { "\(object.key)#\(pixels)" }

    private static let sizes = [96, 144, 240, 360, 512, 720, 1080, 1440, 2048]

    /// The decode size for something drawn `points` wide: nearby sizes share
    /// one decoded copy. 0 (full size) past the biggest.
    static func pixels(points: CGFloat, scale: CGFloat) -> Int {
        let needed = Int((points * max(scale, 1)).rounded(.up))
        return sizes.first { needed <= $0 } ?? 0
    }

    // MARK: Reading

    /// The decoded photo if it's in memory; never touches disk or network.
    func cached(_ memoryKey: String) -> UIImage? {
        memory.object(forKey: memoryKey as NSString)
    }

    /// Memory, then disk, then the network; nil if all of them fail.
    /// Cancelling the caller doesn't cancel the load.
    func image(_ object: StorageObject, pixels: Int) async -> UIImage? {
        let key = Self.memoryKey(object, pixels: pixels)
        if let hit = cached(key) { return hit }
        let task: Task<UIImage?, Never> = lock.withLock {
            if let running = decodes[key] { return running }
            // Registered under the lock, and it unregisters under the same
            // lock, so it can't finish before it's in the table.
            let task = Task.detached(priority: .userInitiated) { [self] () -> UIImage? in
                defer { _ = lock.withLock { decodes.removeValue(forKey: key) } }
                guard let data = await data(for: object),
                      let image = Self.decode(data, maxPixels: pixels) else { return nil }
                memory.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
                return image
            }
            decodes[key] = task
            return task
        }
        return await task.value
    }

    /// The original bytes: the disk copy, else one shared download.
    private func data(for object: StorageObject) async -> Data? {
        let key = object.key
        let task: Task<Data?, Never>? = lock.withLock {
            if let running = fetches[key] { return running }
            if let failed = failedAt[key], Date().timeIntervalSince(failed) < backoff { return nil }
            let task = Task.detached(priority: .userInitiated) { [self] () -> Data? in
                var data: Data?
                #if DEBUG
                // Drawn fresh every launch, so they never come stale off the disk.
                if Self.previewing { data = PreviewPhotos.data(for: object) }
                #endif
                if data == nil { data = readDisk(key) }
                if data == nil { data = await download(object) }
                lock.withLock {
                    fetches.removeValue(forKey: key)
                    if data == nil { failedAt[key] = Date() } else { failedAt.removeValue(forKey: key) }
                }
                return data
            }
            fetches[key] = task
            return task
        }
        return await task?.value
    }

    /// Up to three tries (0.6 s, then 2 s apart) on a network error or a
    /// 5xx. A 4xx (deleted, or not yours to see) isn't retried.
    private func download(_ object: StorageObject) async -> Data? {
        #if DEBUG
        if Self.previewing { return nil }  // offline: nothing goes to the server
        #endif
        let url: URL
        if object.isPublic {
            url = Storage.publicURL(object)
        } else {
            guard let signed = try? await Storage.signedURL(object) else { return nil }
            url = signed
        }
        let delays: [Duration] = [.milliseconds(600), .seconds(2)]
        for attempt in 0...delays.count {
            if attempt > 0 { try? await Task.sleep(for: delays[attempt - 1]) }
            do {
                let (data, response) = try await session.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200, !data.isEmpty {
                    writeDisk(object.key, data)
                    return data
                }
                if (400..<500).contains(status) { return nil }
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: Writing

    /// Bytes you just uploaded, so they draw everywhere without a download.
    func store(_ data: Data, for object: StorageObject) {
        writeDisk(object.key, data)
        _ = lock.withLock { failedAt.removeValue(forKey: object.key) }
    }

    /// Drops one photo from memory and disk (your replaced profile photo).
    func forget(_ object: StorageObject) {
        for size in [0] + Self.sizes {
            memory.removeObject(forKey: Self.memoryKey(object, pixels: size) as NSString)
        }
        try? FileManager.default.removeItem(at: file(object.key))
    }

    /// Sign-out: nothing of anyone's stays behind.
    func clear() {
        memory.removeAllObjects()
        lock.withLock {
            failedAt.removeAll()
            writtenSinceTrim = 0
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: Disk

    /// A stable file name for any key: FNV-1a 64 of its bytes.
    private func file(_ key: String) -> URL {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return folder.appending(path: String(hash, radix: 16) + ".img")
    }

    private func readDisk(_ key: String) -> Data? {
        let url = file(key)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        // Used now: the trim removes the least recently used first.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    private func writeDisk(_ key: String, _ data: Data) {
        try? data.write(to: file(key), options: .atomic)
        let due: Bool = lock.withLock {
            writtenSinceTrim += data.count
            guard writtenSinceTrim >= 25 * 1024 * 1024 else { return false }
            writtenSinceTrim = 0
            return true
        }
        if due { Task.detached(priority: .background) { [self] in trim() } }
    }

    /// Least recently used files go first once the folder passes its limit.
    private func trim() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (url: URL, size: Int, used: Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > diskLimit else { return }
        entries.sort { $0.used < $1.used }
        for entry in entries where total > trimTo {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    // MARK: Decoding

    /// An ImageIO thumbnail `maxPixels` on its long side (never bigger than
    /// the file; 0 for the file's own size), upright, decoded now rather
    /// than on first draw.
    static func decode(_ data: Data, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        var longSide = maxPixels
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? Int,
           let height = props[kCGImagePropertyPixelHeight] as? Int {
            let native = max(width, height)
            longSide = maxPixels > 0 ? min(maxPixels, native) : native
        } else if maxPixels == 0 {
            longSide = 4096
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
