import SwiftUI

/// Shows `content` with the result of `load`: a spinner meanwhile, the error message with Retry on failure.
/// The result lives in the view's state, so coming back from a pushed screen doesn't reload.
/// A failed load runs again by itself when the app returns to the foreground (offline at launch, say).
/// ponytail: no refresh until the app restarts; add pull-to-refresh if merchants need live edits.
@MainActor
struct Loader<Value, Content: View>: View {
    private let load: () async throws -> Value
    private let content: (Value) -> Content
    @State private var value: Value? = nil
    @State private var error: String? = nil
    @State private var attempt = 0
    @Environment(.scenePhase) private var scenePhase

    init(load: @escaping () async throws -> Value, @ViewBuilder content: @escaping (Value) -> Content) {
        self.load = load
        self.content = content
    }

    var body: some View {
        VStack {
            if let value = value {
                content(value)
            } else if let error = error {
                ErrorView(message: error) { attempt += 1 }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, error != nil { attempt += 1 }
        }
        .task(id: attempt) {
            guard value == nil else { return }
            error = nil
            do {
                value = try await load()
            } catch {
                // leaving the screen cancels the load; it runs again when the screen is shown
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

@MainActor
struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(message).multilineTextAlignment(.center)
            Button(action: onRetry) { Text("Retry").onBrand() }.buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}
