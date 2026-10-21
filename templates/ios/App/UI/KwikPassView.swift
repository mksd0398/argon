import ArgonUI
import SwiftUI

/// KwikPass's sign-in (`LOGIN=kwikpass`), one step after another: the phone, its OTP, then, as GoKwik asks, the email
/// (a new phone), the pick of several accounts, or an OTP to the email. `onDone` closes it, signed in or not.
@MainActor
struct KwikPassSignIn: View {
    let store: KwikPassStore
    let onDone: () -> Void

    private enum Step: Equatable {
        case phone
        case otp(phone: String)
        case email
        case choose([String])
        case emailOtp(String)
    }

    @State private var step = Step.phone
    @State private var phone = ""
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String? = nil
    // when the OTP may be sent again (GoKwik's `interval`)
    @State private var resendAt = Date.distantPast
    @State private var canResend = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.l) {
                content
                ErrorText(error)
            }
            .padding(theme.spacing.l)
        }
        .background(theme.colors.paper)
        .task(id: resendAt) {
            canResend = false
            let wait = resendAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            if !Task.isCancelled { canResend = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .phone:
            heading("Sign in with your phone", "We'll send you a code by SMS.")
            ArgonInput(label: "Mobile number (+91)", text: $phone, placeholder: "10-digit number", keyboard: .phone)
            ArgonButton(title: "Send code", isLoading: busy, isEnabled: indianMobile(phone) != nil, fullWidth: true) { sendOtp() }
        case .otp(let number):
            heading("Enter the code", "Sent to +91 \(number)")
            ArgonInputOTP(length: 4, code: $code) { _ in verifyOtp() }
            ArgonButton(title: "Verify", isLoading: busy, isEnabled: code.count == 4, fullWidth: true) { verifyOtp() }
            ArgonButton(title: "Resend code", style: .tertiary, isEnabled: canResend && !busy, fullWidth: true) { sendOtp() }
            ArgonButton(title: "Change number", style: .tertiary, fullWidth: true) { go(.phone) }
        case .email:
            heading("Add your email", "For your orders and account.")
            ArgonInput(label: "Email", text: $email, keyboard: .email)
            ArgonButton(title: "Continue", isLoading: busy, isEnabled: email.contains("@"), fullWidth: true) { submitEmail(email) }
        case .choose(let emails):
            heading("Choose your account", "This number has more than one.")
            VStack(spacing: 0) {
                ForEach(emails, id: \.self) { option in
                    ArgonListItem(title: option, trailing: .chevron) { submitEmail(option) }
                }
            }
            .buttonStyle(.plain)
            .disabled(busy)
        case .emailOtp(let address):
            heading("Check your email", "Enter the code sent to \(address)")
            ArgonInputOTP(length: 4, code: $code) { _ in verifyEmailOtp(address) }
            ArgonButton(title: "Verify", isLoading: busy, isEnabled: code.count == 4, fullWidth: true) { verifyEmailOtp(address) }
            ArgonButton(title: "Resend code", style: .tertiary, isEnabled: !busy, fullWidth: true) {
                run { try await store.sendEmailOtp(address) }
            }
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(title).font(theme.type.title).foregroundStyle(theme.colors.ink).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(theme.type.body).foregroundStyle(theme.colors.muted)
        }
    }

    private func go(_ next: Step) {
        code = ""
        error = nil
        step = next
    }

    private func sendOtp() {
        guard let number = indianMobile(phone) else { return }
        run {
            let interval = try await store.sendOtp(number)
            resendAt = Date().addingTimeInterval(TimeInterval(interval))
            go(.otp(phone: number))
        }
    }

    private func verifyOtp() {
        let entered = code
        run { try await advance(store.verifyOtp(entered)) }
    }

    private func submitEmail(_ address: String) {
        run { try await advance(store.submitEmail(address)) }
    }

    private func verifyEmailOtp(_ address: String) {
        let entered = code
        run { try await advance(store.verifyEmailOtp(address, code: entered)) }
    }

    private func advance(_ next: KwikPassStep) {
        switch next {
        case .emailOtp(let address): go(.emailOtp(address))
        case .chooseEmail(let emails): go(.choose(emails))
        case .enterEmail: go(.email)
        case .done:
            // analytics' `login`, as for Shopify's sign-in (the app has no sign-up event)
            AppGraph.analytics.track(.login)
            onDone()
        }
    }

    /// Runs `block` once at a time; GoKwik's refusal shows under the step.
    private func run(_ block: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                try await block()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
