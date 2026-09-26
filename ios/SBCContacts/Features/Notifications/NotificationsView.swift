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
                NotificationRow(notification: item) {
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
    let onRead: () -> Void

    @Environment(\.services) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(SyncStore.self) private var sync

    @State private var saving = false
    @State private var saved = false

    /// A NEW_MATCH is the one alert with somebody to act on: §11 is "tell me
    /// when a new member matches", and being told is only half of it.
    private var savableMemberId: String? {
        guard notification.type == "NEW_MATCH" else { return nil }
        return notification.memberSbcId
    }

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
                if let memberId = savableMemberId {
                    saveButton(memberId: memberId)
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(notification.createdAt.formatted(Self.dateFormat))
                .font(.sbc(.labelSmall))
                .foregroundStyle(SBCColors.onSurface)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onRead)
        .accessibilityHint(notification.isRead ? "" : "Marquer comme lue")
    }

    /// Saves the matched member straight from the alert. The notification only
    /// carries an sbcId, so the member is fetched first — the same record the
    /// profile screen saves, so the contact written is identical.
    @ViewBuilder
    private func saveButton(memberId: String) -> some View {
        // Laid out as "button, then all the slack" rather than a bare button:
        // inside the row's VStack the label was proposed almost no width, wrapped
        // into slivers too narrow to draw, and left an empty outline behind — the
        // same failure the "Tout / rien" button had. fixedSize() on the Text is
        // what actually guarantees it, so the icon can never be all that renders.
        HStack(spacing: 0) {
            Button {
                Task { await save(memberId: memberId) }
            } label: {
                HStack(spacing: 8) {
                    if saving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: saved ? "checkmark" : "person.badge.plus")
                    }
                    Text(saved ? "Enregistré" : "Enregistrer")
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .buttonStyle(OutlinedButtonStyle(minHeight: 38, fullWidth: false))
            .disabled(saving || saved)

            Spacer(minLength: 0)
        }
    }

    private func save(memberId: String) async {
        saving = true
        defer { saving = false }
        do {
            let member = try await services.directory.profile(sbcId: memberId)
            await addMemberToPhone(member, services: services, toasts: toasts, directory: nil, sync: sync)
            saved = true
        } catch {
            toasts.show(error.localizedDescription)
        }
    }
}
