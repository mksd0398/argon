import Foundation

/// The settings the merchant edits in Krypton's admin page, read from `SETTINGS_URL` (an app Krypton didn't generate has
/// none). Every field is optional and read on its own: a missing one, one of the wrong type or an invalid value is left
/// out (nil) and the built-in value stays; unknown fields are ignored. `analytics` is not read: those ids stay build-time.
struct RemoteSettings: Decodable, Equatable, Sendable {
    /// One welcome page's words; an empty one keeps the page's own.
    struct Page: Decodable, Equatable, Sendable {
        var heading: String? = nil
        var text: String? = nil

        init(heading: String? = nil, text: String? = nil) {
            self.heading = heading
            self.text = text
        }

        // Never throws: a page that isn't an object is a page with no words, so the pages after it keep their place.
        init(from decoder: Decoder) {
            let c = try? decoder.container(keyedBy: Key.self)
            heading = try? c?.decode(String.self, forKey: .heading)
            text = try? c?.decode(String.self, forKey: .text)
        }
    }

    var homeTemplate: HomeTemplate? = nil
    var collectionTemplate: CollectionTemplate? = nil
    /// `#RRGGBB`.
    var accent: String? = nil
    var onboarding: Bool? = nil
    var pages: [Page] = []
    /// Zero means no free shipping (no progress bar in the cart).
    var freeShippingThreshold: Double? = nil
    var showVendor: Bool? = nil
    /// Not empty.
    var judgeMeToken: String? = nil
    /// The tab bar, the top bar and the drawer (screens v2, `Navigation`); nil: the built-in ones.
    var navigation: Navigation? = nil
    /// The strip above the top bar; nil: none.
    var announcement: Announcement? = nil
    /// `appearance.mode`; nil: the device's light or dark.
    var appearance: Appearance? = nil

    private enum Key: String, CodingKey {
        case brand, accent, home, collection, template, onboarding, enabled, pages, heading, text, cart, freeShippingThreshold
        case product, showVendor, reviews, judgeMePublicToken, navigation, announcement, appearance
    }

    init() {}

    init(from decoder: Decoder) throws {
        // the one thing that must hold: an object
        let root = try decoder.container(keyedBy: Key.self)
        func section(_ key: Key) -> KeyedDecodingContainer<Key>? { try? root.nestedContainer(keyedBy: Key.self, forKey: key) }
        func string(_ parent: Key, _ key: Key) -> String? {
            (try? section(parent)?.decode(String.self, forKey: key))?.trimmingCharacters(in: .whitespaces)
        }
        homeTemplate = string(.home, .template).flatMap { HomeTemplate(rawValue: $0.lowercased()) }
        collectionTemplate = string(.collection, .template).flatMap { CollectionTemplate(rawValue: $0.lowercased()) }
        accent = string(.brand, .accent).flatMap { hex in
            hex.count == 7 && hex.first == "#" && hex.dropFirst().allSatisfy { "0123456789abcdefABCDEF".contains($0) } ? hex : nil
        }
        onboarding = try? section(.onboarding)?.decode(Bool.self, forKey: .enabled)
        pages = (try? section(.onboarding)?.decode([Page].self, forKey: .pages)) ?? []
        freeShippingThreshold = (try? section(.cart)?.decode(Double.self, forKey: .freeShippingThreshold))
            .flatMap { $0 >= 0 && $0.isFinite ? $0 : nil }
        showVendor = try? section(.product)?.decode(Bool.self, forKey: .showVendor)
        judgeMeToken = string(.reviews, .judgeMePublicToken).flatMap { $0.isEmpty ? nil : $0 }
        navigation = Navigation.decode(try? root.decode(JSONValue.self, forKey: .navigation))
        announcement = Announcement.decode(try? root.decode(JSONValue.self, forKey: .announcement))
        appearance = Appearance.decode(try? root.decode(JSONValue.self, forKey: .appearance))
    }

    /// The settings in `json`; nil when it isn't JSON or isn't an object.
    init?(json: Data) {
        guard let decoded = try? JSONDecoder().decode(RemoteSettings.self, from: json) else { return nil }
        self = decoded
    }

    /// The free-shipping threshold over the built-in one: these settings' when above zero, none when zero, else `builtIn`.
    func freeShippingThreshold(over builtIn: Double?) -> Double? {
        guard let threshold = freeShippingThreshold else { return builtIn }
        return threshold > 0 ? threshold : nil
    }
}

/// Keeps the merchant's settings in `file` (Application Support's `remote-settings.json`). `load()` reads them as the app
/// launches; `refresh(from:)` then fetches the latest in the background and replaces the file. Fetched values apply at the
/// next launch, never mid-session: a screen never changes under the shopper. `fetch` is URLSession's (tests replace it).
struct RemoteSettingsStore: Sendable {
    let file: URL
    var fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }

    /// The settings fetched last; nil when there are none yet or the file can't be read. Synchronous: it is a small file.
    func load() -> RemoteSettings? {
        (try? Data(contentsOf: file)).flatMap { RemoteSettings(json: $0) }
    }

    /// Fetches `url` (no auth, 5 s) and keeps the answer when it is a 200 with a JSON object. Any failure keeps the file.
    func refresh(from url: URL) async {
        guard let (body, response) = try? await fetch(URLRequest(url: url, timeoutInterval: 5)),
              (response as? HTTPURLResponse)?.statusCode == 200, RemoteSettings(json: body) != nil else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? body.write(to: file, options: .atomic)
    }
}
