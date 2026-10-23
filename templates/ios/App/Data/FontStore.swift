import CoreText
import CryptoKit
import Foundation

/// The merchant's font files (`appearance.fonts`) in `directory` (Caches' `fonts`), each named from a hash of its URL.
/// `register` uses a font only when every one of its files is already there, as the app launches; `download` fetches the
/// missing ones in the background for the next launch: a font never changes mid-session. Any failure keeps Argon's font.
struct FontStore: Sendable {
    let directory: URL
    var fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }

    func file(_ url: String) -> URL {
        directory.appending(path: SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined() + ".ttf")
    }

    /// Registers `font`'s files for this process: CSS weight -> PostScript name; nil when a file is missing or unusable.
    func register(_ font: MerchantFont) -> [Int: String]? {
        var names: [Int: String] = [:]
        for (weight, url) in font.files {
            guard let data = (try? Data(contentsOf: file(url))) ?? builtIn(url), let cgFont = Self.font(data),
                  let name = cgFont.postScriptName as String? else { return nil }
            var error: Unmanaged<CFError>?
            // fails as "already registered" for a second call; the check below decides
            if !CTFontManagerRegisterGraphicsFont(cgFont, &error) { _ = error?.takeRetainedValue() }
            guard CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 12, nil)) as String == name else { return nil }
            names[weight] = name
        }
        return names
    }

    /// Fetches `font`'s files not yet on disk; keeps each that is a 200 and a readable font (atomic write).
    func download(_ font: MerchantFont) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in font.files.values where !FileManager.default.fileExists(atPath: file(url).path) {
            guard let link = URL(string: url),
                  let (body, response) = try? await fetch(URLRequest(url: link, timeoutInterval: 30)),
                  (response as? HTTPURLResponse)?.statusCode == 200, Self.font(body) != nil else { continue }
            try? body.write(to: file(url), options: .atomic)
        }
    }

    /// The file the app was built with for `url` (the CLI's `built-in/fonts/<hash>.ttf`): a built-in font from the first launch.
    func builtIn(_ url: String) -> Data? {
        let name = file(url).deletingPathExtension().lastPathComponent
        return (Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "built-in/fonts")
            ?? Bundle.main.url(forResource: name, withExtension: "ttf")).flatMap { try? Data(contentsOf: $0) }
    }

    private static func font(_ data: Data) -> CGFont? {
        CGDataProvider(data: data as CFData).flatMap { CGFont($0) }
    }
}
