import Foundation
import Observation

/// Where the customer wants things delivered: a six-digit Indian pincode and, when known, its city.
struct DeliveryLocation: Equatable, Sendable {
    let pincode: String
    var city: String? = nil

    /// "560001 · Bengaluru", or the pincode alone.
    var label: String {
        [pincode, city?.trimmingCharacters(in: .whitespaces)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func isPincode(_ text: String) -> Bool {
        text.count == 6 && text.allSatisfy(\.isASCIIDigitValue) && text.first != "0"
    }

    /// `address`'s pincode and city when it is an Indian address with a valid pincode; else nil.
    init?(address: CustomerAddress?) {
        guard let address, let zip = address.zip?.filter({ !$0.isWhitespace }) else { return nil }
        if let country = address.countryCode, country.uppercased() != "IN" { return nil }
        guard Self.isPincode(zip) else { return nil }
        let city = address.city?.trimmingCharacters(in: .whitespaces)
        self.init(pincode: zip, city: city?.isEmpty == false ? city : nil)
    }

    init(pincode: String, city: String? = nil) {
        self.pincode = pincode
        self.city = city
    }
}

private extension Character {
    var isASCIIDigitValue: Bool { isASCII && isNumber }
}

/// Krypton's answer for a pincode (`GET /v1/delivery/{shop}?pincode=`): `date` the order would arrive, nil when the
/// store doesn't deliver there (`serviceable` false); `cod` whether it can be paid on delivery, nil when not known.
struct DeliveryEstimate: Equatable, Sendable {
    let pincode: String
    let serviceable: Bool
    let cod: Bool?
    /// A calendar day (no time zone): read and shown in UTC.
    let date: Date?
    let city: String?

    /// The answer in `json`; nil when it isn't one.
    init?(json: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let pincode = root["pincode"] as? String,
              let serviceable = root["serviceable"] as? Bool else { return nil }
        self.pincode = pincode
        self.serviceable = serviceable
        cod = root["cod"] as? Bool
        date = serviceable ? (root["date"] as? String).flatMap(DeliveryEstimate.day) : nil
        let city = (root["city"] as? String)?.trimmingCharacters(in: .whitespaces)
        self.city = city?.isEmpty == false ? city : nil
    }

    init(pincode: String, serviceable: Bool, cod: Bool?, date: Date?, city: String?) {
        self.pincode = pincode
        self.serviceable = serviceable
        self.cod = cod
        self.date = date
        self.city = city
    }

    static func day(_ text: String) -> Date? {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyy-MM-dd"
        return format.date(from: text)
    }
}

enum DeliveryTone: Equatable { case good, muted, bad }

/// One line of the delivery block.
struct DeliveryLine: Equatable {
    let text: String
    let tone: DeliveryTone
}

/// What the product page says for `estimate`: the date ("Delivery by Thu, 24 Oct") and COD, or that it doesn't deliver there.
func deliveryLines(_ estimate: DeliveryEstimate, locale: Locale = .current) -> [DeliveryLine] {
    guard estimate.serviceable else { return [DeliveryLine(text: "Not delivering to \(estimate.pincode) yet", tone: .bad)] }
    var lines: [DeliveryLine] = []
    if let date = estimate.date {
        let format = DateFormatter()
        format.locale = locale
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "EEE, d MMM"
        lines.append(DeliveryLine(text: "Delivery by \(format.string(from: date))", tone: .good))
    }
    switch estimate.cod {
    case true?: lines.append(DeliveryLine(text: "Cash on delivery available", tone: .muted))
    case false?: lines.append(DeliveryLine(text: "Cash on delivery not available", tone: .muted))
    case nil: break
    }
    return lines
}

/// Krypton's delivery endpoint next to the settings one (`…/v1/settings/{shop}` → `…/v1/delivery/{shop}`); empty without one.
func deliveryEndpoint(_ settingsUrl: String) -> String {
    settingsUrl.contains("/v1/settings/") ? settingsUrl.replacingOccurrences(of: "/v1/settings/", with: "/v1/delivery/") : ""
}

/// The customer's delivery location, kept on the device in `defaults` (`delivery.pincode`, `delivery.city`), and the
/// estimates for it from `url`. Only the pincode leaves the device. Estimates are kept for the session: every product
/// page asks for the same one. `fetch` is URLSession's (tests replace it).
@MainActor
@Observable
final class DeliveryStore {
    private(set) var location: DeliveryLocation?

    private let defaults: UserDefaults
    private let url: String
    private let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private var estimates: [String: DeliveryEstimate] = [:]

    init(
        defaults: UserDefaults,
        url: String,
        fetch: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) {
        self.defaults = defaults
        self.url = url
        self.fetch = fetch
        if let pin = defaults.string(forKey: "delivery.pincode"), DeliveryLocation.isPincode(pin) {
            location = DeliveryLocation(pincode: pin, city: defaults.string(forKey: "delivery.city"))
        }
    }

    func set(_ location: DeliveryLocation) {
        self.location = location
        defaults.set(location.pincode, forKey: "delivery.pincode")
        defaults.set(location.city, forKey: "delivery.city")
    }

    /// The signed-in customer's default address, when the customer has set no location yet.
    func prefill(_ address: CustomerAddress?) {
        if location == nil, let found = DeliveryLocation(address: address) { set(found) }
    }

    /// The estimate for `pincode`; nil when it can't be had (no endpoint, offline, the store turned it off).
    func estimate(_ pincode: String) async -> DeliveryEstimate? {
        if let known = estimates[pincode] { return known }
        guard var parts = URLComponents(string: url), !url.isEmpty else { return nil }
        parts.queryItems = [URLQueryItem(name: "pincode", value: pincode)]
        guard let endpoint = parts.url else { return nil }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        guard let (data, response) = try? await fetch(request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let estimate = DeliveryEstimate(json: data) else { return nil }
        estimates[pincode] = estimate
        return estimate
    }
}
