import SwiftUI

/// "Mise en avant": whether the member's own profile is featured (backend `SpotlightStatus`).
struct SpotlightStatus: Decodable, Sendable {
    var active: Bool
    /// End of an activation by SBC's team; nil while it runs with the SBC subscription.
    var until: Date?

    private enum CodingKeys: String, CodingKey { case active, until }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = c.bool(.active) ?? false
        until = c.date(.until)
    }
}

extension APIClient {
    /// Featured members this member has not saved yet (five at most).
    func spotlightFeatured() async throws -> [StatusBoostEntry] { try await get("/spotlight/featured") }

    func spotlightMe() async throws -> SpotlightStatus { try await get("/spotlight/me") }
}

/// What "En vedette" shows. Owned by the screen that hosts the block: the
/// block itself is empty until it loads, and SwiftUI never starts work on an
/// empty view.
@MainActor
@Observable
final class SpotlightModel {
    private(set) var featured: [StatusBoostEntry] = []
    private(set) var me: SpotlightStatus?

    func load(_ api: APIClient) async {
        async let list = try? api.spotlightFeatured()
        async let status = try? api.spotlightMe()
        featured = await list ?? []
        me = await status
    }
}

/// "En vedette": members who pay to be shown first, at the top of "Qui m'a
/// enregistré" and "Augmenter mes vues WhatsApp". A member saved here leaves
/// the block for good — that contact is won — and the next one takes the place.
///
/// The mise en avant is sold on SBC; on iOS the app never shows its price nor
/// points to where it is bought, it only tells a featured member they are.
struct FeaturedSection: View {
    let model: SpotlightModel

    @Environment(\.services) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(DirectoryStore.self) private var directory
    @Environment(SyncStore.self) private var sync

    @State private var saving: Set<String> = []

    var body: some View {
        if !model.featured.isEmpty {
            Section {
                ForEach(model.featured) { entry in
                    FeaturedRow(entry: entry, saving: saving.contains(entry.sbcId)) {
                        Task { await save(entry) }
                    }
                    .listRowBackground(SBCColors.accent.opacity(0.08))
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").foregroundStyle(SBCColors.accent)
                    Text("En vedette").font(.sbc(.titleSmall, weight: .heavy))
                    Text("· Enregistre-les, ils te verront aussi")
                        .font(.sbc(.bodySmall))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                        .lineLimit(1)
                }
                .textCase(nil)
            }
        }
        if let me = model.me, me.active {
            Section {
                Label(ownText(me), systemImage: "star.fill")
                    .font(.sbc(.bodySmall))
                    .foregroundStyle(SBCColors.onSurface)
                    .tint(SBCColors.accent)
            }
        }
    }

    private func ownText(_ me: SpotlightStatus) -> String {
        guard let until = me.until else {
            return "Ton profil est en vedette : les membres te voient en premier ici."
        }
        let day = until.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR")))
        return "Ton profil est en vedette jusqu'au \(day) : les membres te voient en premier ici."
    }

    private func save(_ entry: StatusBoostEntry) async {
        saving.insert(entry.sbcId)
        defer { saving.remove(entry.sbcId) }
        let ok = await addMemberToPhone(entry.asMember, services: services, toasts: toasts, directory: directory, sync: sync, announce: true)
        // The server leaves out whoever this member saved: refetching brings the next one.
        if ok { await model.load(services.api) }
    }
}

private struct FeaturedRow: View {
    let entry: StatusBoostEntry
    let saving: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(initials: initials(of: entry.displayName), avatarUrl: entry.avatarUrl, radius: 22, rounded: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName).font(.sbc(.bodyMedium, weight: .bold)).lineLimit(1)
                if entry.savedMe {
                    Label("T'a déjà enregistré — enregistre-le en retour", systemImage: "arrow.uturn.left")
                        .font(.sbc(.labelSmall, weight: .semibold))
                        .foregroundStyle(SBCColors.primary)
                        .lineLimit(1)
                } else {
                    Text("T'a déjà enregistré")
                        .font(.sbc(.labelSmall, weight: .semibold))
                        .foregroundStyle(SBCColors.primary)
                }
            }
            Spacer(minLength: 8)
            Button(action: onSave) {
                if saving { ProgressView() } else { Text("Enregistrer") }
            }
            .buttonStyle(FilledButtonStyle(minHeight: 36, fullWidth: false))
            .disabled(saving)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
