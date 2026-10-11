import Foundation

/// The home page the app shows, by kind of store (HOME_TEMPLATE).
enum HomeTemplate: String, CaseIterable, Sendable {
    case fashion, beauty, grocery, b2b

    /// The template named `config`; an unknown or empty value is the default, fashion.
    init(config: String) {
        self = HomeTemplate(rawValue: config.trimmingCharacters(in: .whitespaces).lowercased()) ?? .fashion
    }

    /// The heading and button of the template's three stock banners, shown until the store has banners of its own.
    var bannerCopy: [(heading: String, button: String)] {
        switch self {
        case .fashion:
            return [("The new season", "Shop now"), ("Everyday essentials", "Explore"), ("Made to last", "Discover")]
        case .beauty:
            return [("Your daily ritual", "Shop now"), ("Skin first", "Explore"), ("Colour that stays", "Discover")]
        case .grocery:
            return [("Fresh today", "Shop now"), ("Fill your basket", "Start shopping"), ("Baked this morning", "Order now")]
        case .b2b:
            return [("Stocked and ready to ship", "Browse the catalogue"), ("Tools for the trade", "Shop now"), ("Order by the pallet", "View bulk pricing")]
        }
    }
}

/// Where a collection page keeps its sort and filter controls (COLLECTION_TEMPLATE): a sticky bar at the top, or a
/// floating bar at the bottom.
enum CollectionTemplate: String, CaseIterable, Sendable {
    case top, bottom

    /// The template named `config`; an unknown or empty value is the default, top.
    init(config: String) {
        self = CollectionTemplate(rawValue: config.trimmingCharacters(in: .whitespaces).lowercased()) ?? .top
    }
}

/// The placeholder banners the CLI bundles for the home templates (templates/images, credited in CREDITS.md).
enum StockImages {
    /// Banner `index` (1...3) of `template`, `home-<template>-<index>.jpg`, as a `file:` URL for `StoreImage`; nil when the
    /// bundle doesn't have it.
    static func url(_ template: HomeTemplate, _ index: Int) -> String? {
        let name = "home-\(template.rawValue)-\(index)"
        // a synchronized folder may copy home/ flat into the bundle
        let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "home")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg")
        return url?.absoluteString
    }
}
