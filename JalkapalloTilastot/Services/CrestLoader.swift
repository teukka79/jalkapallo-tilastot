import AppKit
import CryptoKit

/// Lataa joukkueiden logot, tallentaa ne levylle (Caches) ja muistiin.
/// football-data.org palauttaa enimmäkseen SVG-logoja; jos NSImage ei osaa piirtää tiedostoa,
/// palautetaan nil ja näkymä näyttää nimikirjainmerkin.
@MainActor
final class CrestLoader {
    static let shared = CrestLoader()

    private var memory: [URL: NSImage] = [:]
    private var failed: Set<URL> = []
    private var inflight: [URL: Task<NSImage?, Never>] = [:]

    func image(for url: URL) async -> NSImage? {
        if let cached = memory[url] { return cached }
        if failed.contains(url) { return nil }
        if let running = inflight[url] { return await running.value }

        let task = Task { await self.fetch(url) }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        if let result { memory[url] = result } else { failed.insert(url) }
        return result
    }

    private func fetch(_ url: URL) async -> NSImage? {
        let file = Self.cacheFile(for: url)
        var data = try? Data(contentsOf: file)
        if data == nil {
            guard let (downloaded, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            data = downloaded
            try? downloaded.write(to: file, options: .atomic)
        }
        guard let data, let image = NSImage(data: data), image.size.width > 0 else { return nil }
        return image
    }

    private static func cacheFile(for url: URL) -> URL {
        let base = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("crests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name + ".img")
    }
}
