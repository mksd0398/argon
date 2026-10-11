import ArgonUI
import SwiftUI

/// The industrial and B2B home (utilitarian): the trade card (sign in, or the company bought for), one slim banner, the
/// first six categories as a list with "All categories", every rail as a list of five rows with "View all", and a closing
/// "Need a quote?" card. Its top bar is a search field (see HomeView).
@MainActor
struct HomeB2B: View {
    let content: HomeContent
    let onOpen: (Route) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        // nothing to offer a shopper who can't sign in: a store without customer accounts, unless it has the sample one
        let canSignIn = !AppGraph.customerClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || AppGraph.sampleAvailable
        HomeList {
            // signed in without a company: a retail shopper, no card
            if let company = AppGraph.buyer.company {
                CompanyCard(company: company)
            } else if !AppGraph.hasAccount && canSignIn {
                SignInCard()
            }
            if let banner = content.banners.first {
                BannerView(banner: banner, onOpen: onOpen, ratio: 3, headingStyle: \.headline, compact: true)
                    .padding(.horizontal, theme.spacing.l)
            }
            if content.isEmpty { EmptyNote() }
            if !content.categories.isEmpty { CategoryList(categories: Array(content.categories.prefix(6)), onOpen: onOpen) }
            ForEach(Array(content.rails.enumerated()), id: \.offset) { _, rail in
                ProductRows(title: rail.title, cards: Array(rail.items.prefix(5)), onOpen: onOpen, viewAll: content.routeOf(rail))
            }
            QuoteCard(onOpen: onOpen)
        }
    }
}

@MainActor
private struct TradeCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.argonTheme) private var theme

    var body: some View {
        ArgonCard(style: .outlined) {
            VStack(alignment: .leading, spacing: theme.spacing.s) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.l)
        }
        .padding(.horizontal, theme.spacing.l)
    }
}

/// Signed out: trade prices need the buyer's account; the button opens the Account tab.
@MainActor
private struct SignInCard: View {
    @Environment(\.argonTheme) private var theme

    var body: some View {
        TradeCard {
            Text("Sign in for your trade prices").font(theme.type.headline).foregroundStyle(theme.colors.ink)
            ArgonButton(title: "Sign in", size: .s) { AppGraph.tabs.selected = .account }
        }
    }
}

/// Signed in as a company's buyer: the company, the location bought for (a picker when it has several), and what that means.
@MainActor
private struct CompanyCard: View {
    let company: BuyerCompany
    @Environment(\.argonTheme) private var theme

    var body: some View {
        TradeCard {
            Text(company.companyName).font(theme.type.headline).foregroundStyle(theme.colors.ink).lineLimit(1)
            if company.locations.count > 1 {
                ArgonDropdown(
                    label: "Location",
                    options: company.locations.map { $0.name },
                    selectedIndex: company.locations.firstIndex { $0.id == company.locationId },
                    // not tied to this card: the switch finishes even if the shopper leaves the tab
                    onSelect: { index in Task { await AppGraph.buyer.select(company.locations[index].id) } }
                )
            } else if let location = company.location {
                Text(location.name).font(theme.type.body).foregroundStyle(theme.colors.muted).lineLimit(1)
            }
            Text("Your catalogue prices are shown").font(theme.type.label).foregroundStyle(theme.colors.success)
        }
    }
}

/// `categories` as rows with a thumbnail and a chevron; "All categories" opens the Shop tab.
@MainActor
private struct CategoryList: View {
    let categories: [CollectionCard]
    let onOpen: (Route) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Shop by category", actionLabel: "All categories") { AppGraph.tabs.selected = .shop }
            ForEach(categories, id: \.id) { category in
                ArgonListItem(
                    title: category.title,
                    // a collection without a picture keeps the row's shape with an icon
                    leading: category.image.map { ArgonListLeading.image(URL(string: $0.url)) } ?? .icon(.grid),
                    trailing: .chevron,
                    onClick: { onOpen(.collection(category.handle)) }
                )
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, theme.spacing.l)
    }
}

/// The closing card: a quote is asked for on the store's contact page.
@MainActor
private struct QuoteCard: View {
    let onOpen: (Route) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        TradeCard {
            Text("Need a quote?").font(theme.type.headline).foregroundStyle(theme.colors.ink)
            ArgonButton(title: "Contact us", style: .secondary, size: .s) {
                onOpen(.web("https://\(AppGraph.shopDomain)/pages/contact"))
            }
        }
    }
}
