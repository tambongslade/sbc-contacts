import SwiftUI

struct NotificationsView: View {
    let store: NotificationsStore

    var body: some View {
        content
            .background(SBCColors.background)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tout lire") {
                        Task { await store.markAllRead() }
                    }
                    .font(.sbc(.labelLarge, weight: .semibold))
                }
            }
            .task { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(error):
            EmptyStateView(systemImage: "exclamationmark.circle", title: "Erreur", message: error.localizedDescription)
        case let .loaded(items) where items.isEmpty:
            EmptyStateView(
                systemImage: "bell.slash",
                title: "Aucune notification",
                message: "Tu seras notifié quand un membre enregistre ton contact, et des nouveaux membres correspondant à tes critères."
            )
        case let .loaded(items):
            List(items) { item in
                NotificationRow(notification: item)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await store.markRead(item) }
                    }
                    .listRowBackground(SBCColors.surface)
            }
            .listStyle(.plain)
            .refreshable {
                await store.load()
                await store.refreshUnreadCount()
            }
        }
    }
}

private struct NotificationRow: View {
    let notification: AppNotification

    private static let dateFormat = Date.FormatStyle()
        .day(.twoDigits).month(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        .locale(Locale(identifier: "fr_FR"))

    private var icon: String {
        switch notification.type {
        case "NEW_MATCH": "person.badge.plus"
        case "NEW_CORRESPONDENCE": "person.2.badge.plus"
        case "SYNC_AVAILABLE": "arrow.triangle.2.circlepath"
        case "SYNC_ERROR": "exclamationmark.arrow.triangle.2.circlepath"
        // "Quelqu'un t'a enregistré" (§21) — a person acting on you.
        case "CONTACT_SAVED": "person.crop.circle.badge.checkmark"
        default: "bell"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(notification.isRead ? Color(hex: 0xE3E6EC) : SBCColors.primary.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(notification.isRead ? SBCColors.onSurfaceVariant : SBCColors.primary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.sbc(.bodyLarge, weight: notification.isRead ? .regular : .bold))
                    .foregroundStyle(SBCColors.onSurface)
                Text(notification.body)
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(notification.createdAt.formatted(Self.dateFormat))
                .font(.sbc(.labelSmall))
                .foregroundStyle(SBCColors.onSurface)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityHint(notification.isRead ? "" : "Marquer comme lue")
    }
}
