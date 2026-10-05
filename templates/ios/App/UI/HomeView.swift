import SwiftUI

private func loadHome() async throws -> [Section] {
    let brand = try await AppGraph.loadBrand()
    let api = AppGraph.storefront
    return try await homeSections(
        brand,
        home: { try await api.query("HomeScreen", ["handle": "home"]) },
        fallback: { try await api.query("FallbackHome") }
    )
}

@MainActor
struct HomeView: View {
    @Environment(Router.self) private var router

    var body: some View {
        Loader(load: loadHome) { sections in
            if sections.isEmpty {
                Text("Nothing to show yet.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sections.indices, id: \.self) { index in
                            SectionView(section: sections[index])
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { brandTitle }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.open(.search("")) } label: { Label("Search", systemImage: "magnifyingglass") }
            }
        }
    }

    /// The logo, or the shop's name (nothing until the brand has loaded).
    @ViewBuilder private var brandTitle: some View {
        if let brand = AppGraph.brand.value {
            if let logo = brand.logo, let url = URL(string: logo.url) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text(brand.name).bold()
                }
                .frame(maxWidth: 160, maxHeight: 32)
                .accessibilityLabel(brand.name)
            } else {
                Text(brand.name).bold()
            }
        }
    }
}
