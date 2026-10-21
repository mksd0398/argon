import ArgonUI
import CoreLocation
import SwiftUI

/// The delivery block, under availability: "Deliver to 560001 · Bengaluru  Change" and, for that pincode, "Delivery by
/// Thu, 24 Oct" and COD (or that the store doesn't deliver there). A tap opens `DeliverySheet`. Only with
/// `AppGraph.deliveryEnabled`; an estimate that can't be had shows the location alone.
@MainActor
struct ProductDelivery: View {
    @State private var estimate: DeliveryEstimate?
    @State private var picking = false
    @Environment(\.argonTheme) private var theme

    private var store: DeliveryStore { AppGraph.delivery }

    var body: some View {
        let location = store.location
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Button { picking = true } label: {
                HStack(spacing: theme.spacing.xs) {
                    ArgonIcon(name: .location, size: 16, tint: theme.colors.ink)
                    Text(location.map { "Deliver to \($0.label)" } ?? "Check the delivery date")
                        .font(theme.type.label).foregroundStyle(theme.colors.ink).lineLimit(1)
                    Spacer(minLength: theme.spacing.s)
                    Text(location == nil ? "Enter pincode" : "Change").font(theme.type.label).foregroundStyle(theme.colors.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Change delivery location")
            if let shown = estimate, shown.pincode == location?.pincode {
                ForEach(deliveryLines(shown), id: \.text) { line in
                    HStack(spacing: theme.spacing.xs) {
                        ArgonIcon(name: line.tone == .good ? .truck : .info, size: 16, tint: color(line.tone))
                        Text(line.text).font(theme.type.label).foregroundStyle(color(line.tone))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.l)
        .padding(.top, theme.spacing.m)
        // No location yet: the signed-in customer's default address
        .task(id: AppGraph.auth.signedIn) {
            guard AppGraph.auth.signedIn, store.location == nil else { return }
            store.prefill(try? await AppGraph.customerAccount.customer().defaultAddress)
        }
        .task(id: location?.pincode) {
            guard let location else { return estimate = nil }
            estimate = await store.estimate(location.pincode)
            // a typed pincode learns its city from the answer
            if location.city == nil, let city = estimate?.city { store.set(DeliveryLocation(pincode: location.pincode, city: city)) }
        }
        .argonBottomSheet(isPresented: $picking, detents: [.large]) {
            DeliverySheet(current: location) { picked in
                picking = false
                store.set(picked)
            }
        }
    }

    private func color(_ tone: DeliveryTone) -> Color {
        switch tone {
        case .good: return theme.colors.success
        case .muted: return theme.colors.muted
        case .bad: return theme.colors.sale
        }
    }
}

/// Where to deliver: a pincode typed in, the device's location (asked for only on a tap), or one of the signed-in
/// customer's saved addresses.
@MainActor
private struct DeliverySheet: View {
    let current: DeliveryLocation?
    let onPick: (DeliveryLocation) -> Void
    @State private var pincode = ""
    @State private var locating = false
    @State private var error: String?
    @State private var saved: [(name: String, location: DeliveryLocation)] = []
    @State private var finder = LocationFinder()
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            Text("Delivery location").font(theme.type.headline).foregroundStyle(theme.colors.ink)
            ArgonInput(label: "Pincode", text: $pincode, error: error, keyboard: .number)
                .onChange(of: pincode) { _, text in
                    let digits = String(text.filter(\.isNumber).prefix(6))
                    if digits != text { pincode = digits }
                    error = nil
                }
            ArgonButton(title: "Check", isEnabled: DeliveryLocation.isPincode(pincode), fullWidth: true) {
                onPick(DeliveryLocation(pincode: pincode, city: current?.pincode == pincode ? current?.city : nil))
            }
            ArgonButton(title: "Use my location", style: .secondary, icon: .location, isLoading: locating, fullWidth: true) {
                locating = true
                error = nil
                Task {
                    let found = await finder.find()
                    locating = false
                    if let found { onPick(found) } else { error = finder.denied ? "Location is off for this app. Enter your pincode instead." : "Couldn't find your pincode. Enter it instead." }
                }
            }
            if !saved.isEmpty {
                Text("Your addresses").font(theme.type.label).foregroundStyle(theme.colors.muted)
                ForEach(saved, id: \.location.pincode) { entry in
                    Button { onPick(entry.location) } label: {
                        HStack(spacing: theme.spacing.s) {
                            ArgonIcon(name: .location, size: 16, tint: theme.colors.muted)
                            VStack(alignment: .leading) {
                                Text(entry.name).font(theme.type.body).foregroundStyle(theme.colors.ink).lineLimit(1)
                                Text(entry.location.label).font(theme.type.caption).foregroundStyle(theme.colors.muted)
                            }
                            Spacer()
                        }
                        .padding(.vertical, theme.spacing.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(theme.spacing.l)
        .onAppear { pincode = current?.pincode ?? "" }
        .task {
            guard AppGraph.auth.signedIn, let page = try? await AppGraph.customerAccount.addresses() else { return }
            saved = page.items.compactMap { address in
                DeliveryLocation(address: address).map { (address.address1 ?? address.formatted.first ?? $0.pincode, $0) }
            }
        }
    }
}

/// The device's pincode and city: one location fix (permission asked for here, when the shopper tapped), turned into an
/// address by the system geocoder. The coordinates stay on the device. Nil when there is no fix or no Indian pincode.
@MainActor
final class LocationFinder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocation?, Never>?
    private(set) var denied = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func find() async -> DeliveryLocation? {
        denied = false
        guard waiting == nil, let fix = await withCheckedContinuation({ waiting = $0; start() }) else { return nil }
        guard let place = try? await CLGeocoder().reverseGeocodeLocation(fix).first,
              let pin = place.postalCode?.filter(\.isNumber),
              place.isoCountryCode?.uppercased() ?? "IN" == "IN",
              DeliveryLocation.isPincode(pin) else { return nil }
        return DeliveryLocation(pincode: pin, city: place.locality ?? place.subAdministrativeArea)
    }

    private func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: finish(nil, denied: true)
        }
    }

    private func finish(_ location: CLLocation?, denied: Bool = false) {
        self.denied = denied
        waiting?.resume(returning: location)
        waiting = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.waiting != nil else { return }
            switch manager.authorizationStatus {
            case .notDetermined: break
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            default: self.finish(nil, denied: true)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.finish(locations.last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
