import SwiftUI

/// The icons Argon uses, the same names on both platforms (SF Symbols here, Material Symbols on Android).
public enum ArgonIconName: String, CaseIterable, Sendable {
    case home, grid, search, bag, heart, heartFilled, person, menu, close, back
    case chevronRight, chevronDown, chevronUp, plus, minus, filter, sort, share, star, starFilled
    case location, phone, mail, check, info, warning, trash, edit, play, pause
    case truck, returns, leaf, clock, gift, lock, globe, calendar, tag, external, eye, eyeOff

    /// The SF Symbol (all available on iOS 17).
    public var systemName: String {
        switch self {
        case .home: return "house"
        case .grid: return "square.grid.2x2"
        case .search: return "magnifyingglass"
        case .bag: return "bag"
        case .heart: return "heart"
        case .heartFilled: return "heart.fill"
        case .person: return "person"
        case .menu: return "line.3.horizontal"
        case .close: return "xmark"
        case .back: return "chevron.backward"
        case .chevronRight: return "chevron.right"
        case .chevronDown: return "chevron.down"
        case .chevronUp: return "chevron.up"
        case .plus: return "plus"
        case .minus: return "minus"
        case .filter: return "line.3.horizontal.decrease"
        case .sort: return "arrow.up.arrow.down"
        case .share: return "square.and.arrow.up"
        case .star: return "star"
        case .starFilled: return "star.fill"
        case .location: return "mappin.and.ellipse"
        case .phone: return "phone"
        case .mail: return "envelope"
        case .check: return "checkmark"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .trash: return "trash"
        case .edit: return "pencil"
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .truck: return "truck.box"
        case .returns: return "arrow.uturn.backward"
        case .leaf: return "leaf"
        case .clock: return "clock"
        case .gift: return "gift"
        case .lock: return "lock"
        case .globe: return "globe"
        case .calendar: return "calendar"
        case .tag: return "tag"
        case .external: return "arrow.up.right.square"
        case .eye: return "eye"
        case .eyeOff: return "eye.slash"
        }
    }
}

/// An icon, decorative: the control around it carries the accessibility label. Takes the current foreground style
/// unless `tint` is given.
@MainActor
public struct ArgonIcon: View {
    let name: ArgonIconName
    let size: CGFloat
    let tint: Color?

    public init(name: ArgonIconName, size: CGFloat = 20, tint: Color? = nil) {
        self.name = name
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        let image = Image(systemName: name.systemName).font(.system(size: size)).accessibilityHidden(true)
        if let tint = tint {
            image.foregroundStyle(tint)
        } else {
            image
        }
    }
}
