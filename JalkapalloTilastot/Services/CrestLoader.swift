import AppKit
import CryptoKit

/// Lataa joukkueiden logot, tallentaa ne pysyvästi levylle (Application Support/crests) ja muistiin.
/// football-data.org palauttaa enimmäkseen SVG-logoja; jos NSImage ei osaa piirtää tiedostoa,
/// palautetaan nil ja näkymä näyttää nimikirjainmerkin.
@MainActor
final class CrestLoader {
    static let shared = CrestLoader()

    private var originals: [URL: NSImage] = [:]
    private var memory: [String: NSImage] = [:]
    private var failed: [URL: Date] = [:]
    /// Epäonnistunutta latausta yritetään uudelleen tämän ajan kuluttua (verkkokatko ei jää pysyväksi).
    private let retryAfter: TimeInterval = 120
    private var inflight: [URL: Task<NSImage?, Never>] = [:]

    /// `side` = näyttökoko pisteinä. Iso logo piirretään kerran valmiiksi 2x-kokoon (korkealaatuinen skaalaus),
    /// jolloin se on terävä eikä SwiftUI joudu pienentämään satojen pikselien kuvaa lennosta.
    func image(for url: URL, side: CGFloat = 0) async -> NSImage? {
        let key = "\(url.absoluteString)#\(Int(side))"
        if let cached = memory[key] { return cached }
        guard let original = await originalImage(for: url) else { return nil }
        let result = side > 0 ? Self.scaled(original, to: side) : original
        memory[key] = result
        return result
    }

    private func originalImage(for url: URL) async -> NSImage? {
        if let cached = originals[url] { return cached }
        if let when = failed[url], Date().timeIntervalSince(when) < retryAfter { return nil }
        if let running = inflight[url] { return await running.value }

        let task = Task { await self.fetch(url) }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        if let result { originals[url] = result; failed[url] = nil } else { failed[url] = Date() }
        return result
    }

    /// Piirtää kuvan neliöön (kuvasuhde säilyy) 2x-tarkkuudella.
    private static func scaled(_ image: NSImage, to side: CGFloat) -> NSImage {
        let scale: CGFloat = 2
        let px = max(1, Int((side * scale).rounded()))
        guard image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let target = CGFloat(px)
        let ratio = min(target / image.size.width, target / image.size.height)
        let w = image.size.width * ratio, h = image.size.height * ratio
        image.draw(in: NSRect(x: (target - w) / 2, y: (target - h) / 2, width: w, height: h),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: NSSize(width: side, height: side))
        out.addRepresentation(rep)
        return out
    }

    private func fetch(_ url: URL) async -> NSImage? {
        let file = Self.cacheFile(for: url)
        if let data = Self.readStored(url, file), let image = NSImage(data: data), image.size.width > 0 {
            return image
        }
        try? FileManager.default.removeItem(at: file) // vioittunut tiedosto ladataan uudelleen
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            guard let (downloaded, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: downloaded), image.size.width > 0 else { continue }
            try? downloaded.write(to: file, options: .atomic)
            return image
        }
        return nil
    }

    /// Pysyvä tallennus: Application Support (ei tyhjene automaattisesti). Vanha Caches-kopio luetaan ja siirretään.
    private static func readStored(_ url: URL, _ file: URL) -> Data? {
        if let data = try? Data(contentsOf: file) { return data }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined() + ".img"
        guard let caches = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: false) else { return nil }
        let old = caches.appendingPathComponent("crests", isDirectory: true).appendingPathComponent(name)
        guard let data = try? Data(contentsOf: old) else { return nil }
        try? data.write(to: file, options: .atomic)
        return data
    }

    private static func cacheFile(for url: URL) -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("crests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name + ".img")
    }
}
