import ArgonUI
import SwiftUI

@MainActor
private func loadPolicy(_ handle: String) async throws -> ShopPolicy {
    guard let policy = try await AppGraph.storefront.policies().policy(handle) else { throw NotFound(what: "Policy") }
    return policy
}

/// One of the shop's policies (route `policy/<handle>`: privacy-policy, terms-of-service, refund-policy, shipping-policy,
/// ...), its body shown as the product description is.
@MainActor
struct PolicyView: View {
    let handle: String
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Loader(load: { try await loadPolicy(handle) }, skeleton: .text) { policy in
            ScrollView {
                HtmlText(html: policy.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(theme.spacing.l)
            }
            .argonTopBar(title: policy.title)
        }
        .background(theme.colors.paper)
    }
}
