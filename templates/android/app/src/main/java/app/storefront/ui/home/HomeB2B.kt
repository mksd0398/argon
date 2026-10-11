package app.storefront.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonCard
import app.argon.ui.components.ArgonCardStyle
import app.argon.ui.components.ArgonDropdown
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonListItem
import app.argon.ui.components.ArgonListLeading
import app.argon.ui.components.ArgonListTrailing
import app.storefront.AppGraph
import app.storefront.data.BuyerCompany
import app.storefront.data.CollectionCard
import app.storefront.data.HomeContent
import app.storefront.data.Route
import app.storefront.ui.AppTab
import app.storefront.ui.SectionHeader
import kotlinx.coroutines.launch

/**
 * The industrial and B2B home (utilitarian): the trade card (sign in, or the company bought for), one slim banner, the
 * first six categories as a list with "All categories", every rail as a list of five rows with "View all", and a closing
 * "Need a quote?" card. Its top bar is a search field (see HomeScreen).
 */
@Composable
fun HomeB2B(content: HomeContent, onOpen: (Route) -> Unit) {
    val spacing = ArgonTheme.spacing
    val hasAccount by AppGraph.hasAccount.collectAsState()
    val company by AppGraph.buyer.company.collectAsState()
    val buyer = company
    // nothing to offer a shopper who can't sign in: a store without customer accounts, unless it has the sample one
    val canSignIn = AppGraph.customerClientId.isNotBlank() || AppGraph.sampleAvailable
    val banner = content.banners.firstOrNull()
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = spacing.s, bottom = spacing.xl),
        verticalArrangement = Arrangement.spacedBy(spacing.xl),
    ) {
        // signed in without a company: a retail shopper, no card
        if (buyer != null) item { CompanyCard(buyer) } else if (!hasAccount && canSignIn) item { SignInCard() }
        if (banner != null) item { BannerView(banner, onOpen, ratio = 3f, Modifier.padding(horizontal = spacing.l), ArgonTheme.type.headline, compact = true) }
        if (content.isEmpty) item { EmptyNote() }
        if (content.categories.isNotEmpty()) item { CategoryList(content.categories.take(6), onOpen) }
        items(content.rails) { rail -> ProductRows(rail.title, rail.items.take(5), onOpen, viewAll = content.routeOf(rail)) }
        item { QuoteCard(onOpen) }
    }
}

@Composable
private fun TradeCard(content: @Composable () -> Unit) =
    ArgonCard(Modifier.fillMaxWidth().padding(horizontal = ArgonTheme.spacing.l), style = ArgonCardStyle.Outlined) {
        Column(Modifier.fillMaxWidth().padding(ArgonTheme.spacing.l), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) { content() }
    }

/** Signed out: trade prices need the buyer's account; the button opens the Account tab. */
@Composable
private fun SignInCard() = TradeCard {
    Text("Sign in for your trade prices", style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
    ArgonButton("Sign in", size = ArgonSize.S) { AppGraph.tabs.select(AppTab.Account) }
}

/** Signed in as a company's buyer: the company, the location bought for (a picker when it has several), and what that means. */
@Composable
private fun CompanyCard(company: BuyerCompany) = TradeCard {
    Text(company.companyName, style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
    if (company.locations.size > 1) {
        ArgonDropdown(
            "Location",
            company.locations.map { it.name },
            selectedIndex = company.locations.indexOfFirst { it.id == company.locationId }.takeIf { it >= 0 },
            // on the app's scope: the switch finishes even if the shopper leaves the tab
            onSelect = { index -> AppGraph.scope.launch { AppGraph.buyer.select(company.locations[index].id) } },
        )
    } else {
        company.location?.let { Text(it.name, style = ArgonTheme.type.body, color = ArgonTheme.colors.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) }
    }
    Text("Your catalogue prices are shown", style = ArgonTheme.type.label, color = ArgonTheme.colors.success)
}

/** [categories] as rows with a thumbnail and a chevron; "All categories" opens the Shop tab. */
@Composable
private fun CategoryList(categories: List<CollectionCard>, onOpen: (Route) -> Unit) = Column {
    SectionHeader("Shop by category", Modifier.padding(horizontal = ArgonTheme.spacing.l), actionLabel = "All categories") {
        AppGraph.tabs.select(AppTab.Shop)
    }
    for (category in categories) {
        ArgonListItem(
            category.title,
            // a collection without a picture keeps the row's shape with an icon
            leading = category.image?.let { ArgonListLeading.Image(it.url) } ?: ArgonListLeading.Icon(ArgonIconName.Grid),
            trailing = ArgonListTrailing.Chevron,
            onClick = { onOpen(Route.Collection(category.handle)) },
        )
    }
}

/** The closing card: a quote is asked for on the store's contact page. */
@Composable
private fun QuoteCard(onOpen: (Route) -> Unit) = TradeCard {
    Text("Need a quote?", style = ArgonTheme.type.headline, color = ArgonTheme.colors.ink)
    ArgonButton("Contact us", style = ArgonButtonStyle.Secondary, size = ArgonSize.S) {
        onOpen(Route.Web("https://${AppGraph.shopDomain}/pages/contact"))
    }
}
