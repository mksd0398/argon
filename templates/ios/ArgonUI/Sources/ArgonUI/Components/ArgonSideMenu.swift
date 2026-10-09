import SwiftUI

/// A menu that slides over from the leading edge on a dimmed scrim (iOS has no drawer). Put it in an `.overlay` of the
/// screen. A tap on the scrim, a swipe back towards the edge, or VoiceOver's escape gesture calls `onDismiss`.
@MainActor
public struct ArgonSideMenu<Header: View, Footer: View, Content: View>: View {
    let isOpen: Bool
    let onDismiss: () -> Void
    let header: Header
    let footer: Footer
    let content: Content
    @GestureState private var drag: CGFloat = 0
    @Environment(\.argonTheme) private var theme

    public init(
        isOpen: Bool,
        onDismiss: @escaping () -> Void,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder content: () -> Content
    ) {
        self.isOpen = isOpen
        self.onDismiss = onDismiss
        self.header = header()
        self.footer = footer()
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width * 0.82, 340)
            ZStack(alignment: .leading) {
                Color.black.opacity(isOpen ? 0.4 : 0)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ScrollView {
                        VStack(alignment: .leading, spacing: theme.spacing.xxs) { content }
                            .padding(theme.spacing.s)
                    }
                    footer
                }
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background { theme.colors.surface.ignoresSafeArea() }
                .offset(x: isOpen ? min(drag, 0) : -width - 24)
                .gesture(
                    DragGesture()
                        .updating($drag) { value, state, _ in state = value.translation.width }
                        .onEnded { value in
                            if value.translation.width < -width / 3 || value.predictedEndTranslation.width < -width / 2 { onDismiss() }
                        }
                )
            }
            .animation(.easeOut(duration: 0.25), value: isOpen)
        }
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
        .accessibilityAction(.escape, onDismiss)
    }
}

extension ArgonSideMenu where Header == EmptyView, Footer == EmptyView {
    public init(isOpen: Bool, onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.init(isOpen: isOpen, onDismiss: onDismiss, header: { EmptyView() }, footer: { EmptyView() }, content: content)
    }
}

/// A side menu row: icon, title, an optional count badge, and a chevron when it opens a submenu.
@MainActor
public struct ArgonSideMenuItem: View {
    let title: String
    let icon: ArgonIconName?
    let badge: Int?
    let isSelected: Bool
    let hasChildren: Bool
    let onClick: () -> Void
    @Environment(\.argonTheme) private var theme

    public init(
        title: String,
        icon: ArgonIconName? = nil,
        badge: Int? = nil,
        isSelected: Bool = false,
        hasChildren: Bool = false,
        onClick: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.badge = badge
        self.isSelected = isSelected
        self.hasChildren = hasChildren
        self.onClick = onClick
    }

    public var body: some View {
        Button(action: onClick) {
            HStack(spacing: theme.spacing.m) {
                if let icon = icon { ArgonIcon(name: icon, size: 20, tint: theme.colors.ink) }
                Text(title)
                    .font(isSelected ? theme.type.headline : theme.type.body)
                    .foregroundStyle(theme.colors.ink)
                Spacer(minLength: theme.spacing.s)
                if let badge = badge { ArgonBadge(count: badge) }
                if hasChildren { ArgonIcon(name: .chevronRight, size: 14, tint: theme.colors.muted) }
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(minHeight: 48)
            .background(isSelected ? theme.colors.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: theme.radius.m))
            .contentShape(Rectangle())
        }
        .buttonStyle(ArgonPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
