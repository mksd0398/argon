import SwiftUI

/// A modal's button.
public struct ArgonModalAction {
    public let title: String
    public let isDestructive: Bool
    public let action: () -> Void

    public init(_ title: String, isDestructive: Bool = false, action: @escaping () -> Void = {}) {
        self.title = title
        self.isDestructive = isDestructive
        self.action = action
    }
}

/// A native alert: title, message, a primary action and an optional secondary (cancel) one. Use `.argonModal(...)`.
public struct ArgonModal: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let primaryAction: ArgonModalAction
    let secondaryAction: ArgonModalAction?

    public func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button(primaryAction.title, role: primaryAction.isDestructive ? .destructive : nil, action: primaryAction.action)
            if let secondary = secondaryAction {
                Button(secondary.title, role: .cancel, action: secondary.action)
            }
        } message: {
            Text(message)
        }
    }
}

/// A full-screen cover with a title and a close button. Use `.argonFullScreenModal(...)`.
public struct ArgonFullScreenModal<ModalContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let modalContent: () -> ModalContent
    @Environment(\.argonTheme) var theme

    public func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            NavigationStack {
                modalContent()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { isPresented = false } label: { ArgonIcon(name: .close) }
                                .accessibilityLabel("Close")
                        }
                    }
            }
            .environment(\.argonTheme, theme)
            .tint(theme.colors.accent)
        }
    }
}

public enum ArgonSheetDetent: Hashable, Sendable {
    case medium, large
}

/// A native bottom sheet at the given heights, with a drag indicator. Use `.argonBottomSheet(...)`.
public struct ArgonBottomSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let detents: Set<ArgonSheetDetent>
    let sheetContent: () -> SheetContent
    @Environment(\.argonTheme) var theme

    public func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            sheetContent()
                .presentationDetents(Set(detents.map { $0 == .medium ? PresentationDetent.medium : .large }))
                .presentationDragIndicator(.visible)
                .environment(\.argonTheme, theme)
                .tint(theme.colors.accent)
        }
    }
}

extension View {
    public func argonModal(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        primaryAction: ArgonModalAction,
        secondaryAction: ArgonModalAction? = nil
    ) -> some View {
        modifier(ArgonModal(
            isPresented: isPresented, title: title, message: message,
            primaryAction: primaryAction, secondaryAction: secondaryAction
        ))
    }

    public func argonFullScreenModal<ModalContent: View>(
        isPresented: Binding<Bool>,
        title: String,
        @ViewBuilder content: @escaping () -> ModalContent
    ) -> some View {
        modifier(ArgonFullScreenModal(isPresented: isPresented, title: title, modalContent: content))
    }

    public func argonBottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        detents: Set<ArgonSheetDetent> = [.medium, .large],
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(ArgonBottomSheet(isPresented: isPresented, detents: detents, sheetContent: content))
    }
}
