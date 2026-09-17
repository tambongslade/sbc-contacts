import SwiftUI

/// "Qui m'a enregistré ?" (cahier §21) — the members who saved you.
///
/// The counterpart of "Mes contacts SBC": that screen says who you kept, this
/// one says who kept you. Only additions a device actually confirmed are
/// listed, never someone who merely looked at your profile.
struct SavedMeView: View {
    @Environment(\.services) private var services

    private enum LoadState {
        case loading
        case loaded(Paginated<SavedMeEntry>)
        case failed(Error)
    }

    @State private var state: LoadState = .loading

    var body: some View {
        content
            .navigationTitle("Qui m'a enregistré")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ListSkeleton()
        case let .failed(error):
            EmptyStateView(systemImage: "exclamationmark.circle", title: "Erreur", message: error.localizedDescription) {
                Button("Réessayer") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
        case let .loaded(page) where page.items.isEmpty:
            EmptyStateView(
                systemImage: "person.crop.circle.badge.plus",
                title: "Personne pour le moment",
                message: "Quand un membre enregistre ton contact dans son téléphone, il apparaît ici — et tu reçois une notification."
            )
        case let .loaded(page):
            List {
                Section {
                    ForEach(page.items) { SavedMeRow(entry: $0) }
                } header: {
                    Label(
                        page.total == 1 ? "1 membre a enregistré ton contact" : "\(page.total) membres ont enregistré ton contact",
                        systemImage: "checkmark.shield"
                    )
                    .font(.montserrat(.subheadline, .semibold))
                    .foregroundStyle(SBCColors.secondaryDark)
                    .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            state = .loaded(try await services.sync.savedMe())
        } catch {
            if case .loaded = state { return }
            state = .failed(error)
        }
    }
}

private struct SavedMeRow: View {
    @Environment(\.services) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(SyncStore.self) private var sync

    let entry: SavedMeEntry

    /// Local so the row answers the tap immediately; the list is only refetched
    /// on a pull-to-refresh, and re-reading it just to flip one button would
    /// scroll the member back to the top.
    @State private var saved: Bool?
    @State private var saving = false

    private var isSaved: Bool { saved ?? entry.alreadySaved }

    var body: some View {
        let when = Self.relative(entry.savedAt)
        let subtitle = [entry.profession, entry.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")

        HStack(spacing: 10) {
            MemberAvatar(initials: initials(of: entry.displayName), avatarUrl: entry.avatarUrl, radius: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(.montserrat(.body, .semibold))
                Text(subtitle.isEmpty ? when : "\(subtitle) · \(when)")
                    .font(.montserrat(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The reciprocal (§21): they kept you, so the one thing this row is
            // for is keeping them back — it comes before WhatsApp, the follow-up.
            addBackButton
            WhatsAppButton(
                phoneNumber: entry.phoneNumber,
                contactName: entry.displayName,
                size: 36
            )
        }
        .padding(.vertical, 2)
    }

    /// "Ajouter" / "Ajouté", as a compact capsule rather than an icon: this is
    /// the action the screen exists for, and an icon alone would not say which
    /// direction the contact goes.
    @ViewBuilder
    private var addBackButton: some View {
        if isSaved {
            Label("Ajouté", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.montserrat(.caption, .semibold))
                .foregroundStyle(SBCColors.success)
                .accessibilityLabel("Déjà dans ton répertoire")
        } else {
            Button { Task { await addBack() } } label: {
                if saving {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Ajouter").font(.montserrat(.caption, .semibold))
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(SBCColors.primary)
            .disabled(saving)
        }
    }

    /// Writes them into the phone book and records it, so they also turn up in
    /// "Mes contacts SBC" — that screen reads the backend, not the phone book.
    @MainActor
    private func addBack() async {
        saving = true
        defer { saving = false }

        let service = ContactService()
        guard await service.requestPermission() else {
            toasts.show("Permission contacts refusée")
            return
        }

        // Already in the phone book: nothing to write, but it still belongs in
        // "Mes contacts SBC" — that list reports what is on the device, and it is.
        var present = false
        if let phone = entry.phoneNumber, !phone.isEmpty {
            present = await service.existsByPhone(phone)
        }

        var deviceContactId: String?
        if !present {
            let result = await service.addSBCContact(
                displayName: entry.displayName,
                phone: entry.phoneNumber,
                profession: entry.profession
            )
            guard result.success else {
                toasts.show("Échec : \(result.error ?? "")")
                return
            }
            deviceContactId = result.deviceContactId
        }

        var recorded = true
        do {
            recorded = try await services.sync.recordSingleContact(
                memberSbcId: entry.actorSbcId,
                deviceContactId: deviceContactId
            )
        } catch {
            // The contact IS on the phone; only the bookkeeping failed. Calling
            // it a failure outright would send the member to save it twice.
            recorded = false
        }

        saved = true
        await sync.loadSummary()
        toasts.show(present
            ? "Déjà dans ton répertoire"
            : recorded
                ? "Contact ajouté — visible dans « Mes contacts SBC »"
                : "Contact ajouté au téléphone (pas encore synchronisé au serveur)")
    }

    /// Relative for the recent past, absolute once "il y a N jours" stops being
    /// easier to read than the date itself.
    static func relative(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "à l'instant" }
        if seconds < 3600 { return "il y a \(Int(seconds / 60)) min" }
        if seconds < 86_400 { return "il y a \(Int(seconds / 3600)) h" }
        if seconds < 7 * 86_400 { return "il y a \(Int(seconds / 86_400)) j" }
        return date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "fr_FR")))
    }
}
