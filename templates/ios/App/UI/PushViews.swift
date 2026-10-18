import ArgonUI
import SwiftUI

// Where the shopper turns push on (an app built with `PUSH` only): the Account screen's "Notifications" switch, and
// the one offer after a first purchase. Never at first launch.

/// "Notifications" with its switch (`AppGraph.push`), for anyone, signed in or not; nothing in an app without push.
/// Turning it on asks the OS first: refused, it stays off and says where to allow them.
@MainActor
struct NotificationsRow: View {
    @State private var busy = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        if let push = AppGraph.push {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Notifications")
                ArgonSwitch(isOn: push.optedIn, label: "Offers and news") { on in
                    if busy { return }
                    busy = true
                    Task {
                        await turn(push, on)
                        busy = false
                    }
                }
                .frame(minHeight: 44)
                Text("New arrivals and offers from \(AppGraph.brand.value?.name ?? AppGraph.appName).")
                    .font(theme.type.caption)
                    .foregroundStyle(theme.colors.muted)
            }
        }
    }
}

/// Turns `push` on (asking the OS) or off; a refusal or a failure is said in a toast.
@MainActor
private func turn(_ push: PushStore, _ on: Bool) async {
    guard on else {
        await push.disable()
        return
    }
    do {
        if !(try await push.enable()) { AppGraph.toast.show("Notifications are off for this app. Turn them on in Settings.") }
    } catch {
        AppGraph.toast.show("Notifications couldn't be turned on. Try again later.")
    }
}

/// The offer of notifications after a first purchase (`PushStore.offerAfterPurchase`), as a sheet over the tabs: what
/// they are for, then the OS prompt. Made once, whatever the answer.
struct PushOffer: ViewModifier {
    func body(content: Content) -> some View {
        if let push = AppGraph.push {
            content.argonBottomSheet(
                isPresented: Binding(get: { push.offering }, set: { if !$0 { close(push) } }),
                detents: [.medium]
            ) {
                OfferSheet(push: push) { close(push) }
            }
        } else {
            content
        }
    }

    @MainActor
    private func close(_ push: PushStore) {
        push.offering = false
        push.markAsked()
    }
}

@MainActor
private struct OfferSheet: View {
    let push: PushStore
    let onClose: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.l) {
            ArgonIcon(name: .gift, size: 32, tint: theme.colors.ink)
            Text("Thanks for your order").font(theme.type.title).foregroundStyle(theme.colors.ink)
            Text("Turn on notifications to hear about new arrivals and offers from \(AppGraph.brand.value?.name ?? AppGraph.appName) first.")
                .font(theme.type.body)
                .foregroundStyle(theme.colors.muted)
            VStack(spacing: theme.spacing.s) {
                ArgonButton(title: "Turn on notifications", fullWidth: true) {
                    onClose()
                    Task { await turn(push, true) }
                }
                ArgonButton(title: "Not now", style: .tertiary, fullWidth: true, action: onClose)
            }
        }
        .padding(theme.spacing.l)
    }
}
