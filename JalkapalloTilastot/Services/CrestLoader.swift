import AppKit
import CryptoKit

/// Lataa joukkueiden logot, tallentaa ne pysyvästi levylle (Application Support/crests) ja muistiin.
/// football-data.org palauttaa enimmäkseen SVG-logoja; jos NSImage ei osaa piirtää tiedostoa,
/// palautetaan nil ja näkymä näyttää nimikirjainmerkin.
@MainActor
final class CrestLoader {
    static let shared = CrestLoader()

    private var memory: [URL: NSImage] = [:]
    private var failed: [URL: Date] = [:]
    /// Epäonnistunutta latausta yritetään uudelleen tämän ajan kuluttua (verkkokatko ei jää pysyväksi).
    private let retryAfter: TimeInterval = 120
    private var inflight: [URL: Task<NSImage?, Never>] = [:]

    func image(for url: URL) async -> NSImage? {
        if let cached = memory[url] { return cached }
        if let when = failed[url], Date().timeIntervalSince(when) < retryAfter { return nil }
        if let running = inflight[url] { return await running.value }

        let task = Task { await self.fetch(url) }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        if let result { memory[url] = result; failed[url] = nil } else { failed[url] = Date() }
        return result
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
