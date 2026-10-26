import SwiftUI

struct FavoritesView: View {
    @Environment(FavoritesStore.self) private var store
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Group {
            // Favourites are SBC members: an SBC Network account gets the paywall.
            if auth.user?.isNetworkAccount == true {
                SubscriptionGate(networkAccount: true)
            } else {
                content.task { await store.load() }
            }
        }
        .background(SBCColors.background)
        .navigationTitle("Mes favoris")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            EmptyStateView(systemImage: "exclamationmark.circle", title: "Erreur", message: error.localizedDescription)
        case let .loaded(members) where members.isEmpty:
            EmptyStateView(
                systemImage: "star",
                title: "Aucun favori",
                message: "Ajoute des membres à tes favoris pour les retrouver ici."
            )
        case let .loaded(members):
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(members) { MemberCard(member: $0) }
                }
                .padding(.vertical, 8)
            }
            .refreshable { await store.load() }
        }
    }
}
