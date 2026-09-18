import SwiftUI

/// Synchronisation home (cahier §10, §16, §17, §21): the dashboard, the ways
/// into "Mes contacts SBC" and "Qui m'a enregistré", and the saved criteria.
///
/// The dashboard leads with a ring rather than a number grid. The one thing
/// this screen has to say to a member who has configured nothing is "you have
/// configured nothing" — a "0" among four other zeroes says it far too quietly,
/// and the four counters below are the detail you read *after* that.
struct SyncView: View {
    @Environment(SyncStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch store.summary {
                case .loading: SummarySkeleton()
                case .failed: EmptyView()
                case let .loaded(summary): SummaryDashboard(summary: summary)
                }

                VStack(spacing: 0) {
                    ShortcutRow(route: .syncedContacts, systemImage: "person.text.rectangle.fill", label: "Mes contacts SBC", tint: SBCColors.primary)
                    Divider().padding(.leading, 62)
                    // The counterpart: that screen says who you kept, this one
                    // says who kept you (§21).
                    ShortcutRow(route: .savedMe, systemImage: "person.crop.circle.badge.checkmark", label: "Qui m'a enregistré", tint: SBCColors.secondaryDark)
                    Divider().padding(.leading, 62)
                    // Moved out of the toolbar: that slot now carries the live
                    // state, and the history is a destination like the two above.
                    ShortcutRow(route: .syncHistory, systemImage: "clock.arrow.circlepath", label: "Historique", tint: SBCColors.accent)
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 4)

                Text("MES CRITÈRES")
                    .font(.montserrat(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(EdgeInsets(top: 24, leading: 32, bottom: 6, trailing: 16))

                switch store.criteria {
                case .loading:
                    CardListSkeleton(rows: 3)
                case let .failed(error):
                    EmptyStateView(systemImage: "exclamationmark.circle", title: "Erreur", message: error.localizedDescription) {
                        Button("Réessayer") { Task { await store.loadCriteria() } }
                            .buttonStyle(.borderedProminent)
                    }
                case let .loaded(list) where list.isEmpty:
                    EmptyStateView(
                        systemImage: "slider.horizontal.3",
                        title: "Aucun critère",
                        message: "Définis les catégories de membres à enregistrer : pays, région, profession, centres d'intérêt, âge."
                    )
                case let .loaded(list):
                    VStack(spacing: 10) {
                        ForEach(list) { CriteriaCard(criteria: $0) }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 96)
        }
        .refreshable { await store.load() }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottomTrailing) {
            NavigationLink(value: AppRoute.criteriaNew) {
                Label("Nouveau critère", systemImage: "plus")
                    .font(.montserrat(.body, .semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(16)
        }
        .navigationTitle("Synchro")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { LivePill() }
        }
        .task { await store.load() }
    }
}

/// "Live" — the sync is always on, the screen just says so out loud.
private struct LivePill: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(SBCColors.secondary).frame(width: 8, height: 8)
            Text("Live")
                .font(.montserrat(.footnote, .semibold))
                .foregroundStyle(SBCColors.secondaryDark)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(SBCColors.secondary.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Synchronisation active")
    }
}

/// The hero ring plus the four counters.
private struct SummaryDashboard: View {
    let summary: SyncSummary

    var body: some View {
        VStack(spacing: 10) {
            CriteriaRingCard(summary: summary)
            // 2×2 rather than a row of four: "Correspondances" cannot be read
            // at a quarter of a phone's width.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(label: "Synchronisés", value: summary.syncedCount, systemImage: "checkmark.circle.fill", tint: SBCColors.success, route: .syncedContacts)
                StatTile(label: "En attente", value: summary.pendingCount, systemImage: "clock.fill", tint: SBCColors.accent, route: .syncedContacts)
                StatTile(label: "Correspondances", value: summary.currentMatches, systemImage: "person.2.fill", tint: SBCColors.primary)
                StatTile(label: "Critères", value: summary.activeCriteria, systemImage: "slider.horizontal.3", tint: SBCColors.secondaryDark)
            }
            if summary.failedCount > 0 {
                Label("\(summary.failedCount) échec(s) — voir Mes contacts SBC", systemImage: "exclamationmark.circle")
                    .font(.montserrat(.footnote))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16))
    }
}

/// The hero: how many of your criteria are running, as a ring.
///
/// Reads "N / M CRITÈRES" — a ratio, not a total, because a criterion that has
/// been paused is still one you wrote and the member needs to see the gap. With
/// nothing configured the ring is empty and the card says what to do about it,
/// which is the only useful thing this screen can say at that point.
private struct CriteriaRingCard: View {
    let summary: SyncSummary

    private var configured: Bool { summary.criteriaCount > 0 }
    private var fraction: Double {
        summary.criteriaCount == 0 ? 0 : Double(summary.activeCriteria) / Double(summary.criteriaCount)
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 13)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(
                        AngularGradient(
                            colors: [SBCColors.primary, SBCColors.secondary],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 13, lineCap: .round)
                    )
                    // From 12 o'clock — the direction a progress ring is read.
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text(summary.activeCriteria, format: .number.locale(Locale(identifier: "fr_FR")))
                        .font(.montserrat(.largeTitle, .bold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("/\(summary.criteriaCount) CRITÈRES")
                        .font(.montserrat(.caption2, .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 172, height: 172)
            .padding(.top, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(summary.activeCriteria) critère(s) actif(s) sur \(summary.criteriaCount)")

            Label(
                configured
                    ? "\(summary.currentMatches) membre(s) à synchroniser"
                    : "Configure pour débloquer la magie",
                systemImage: configured ? "arrow.triangle.2.circlepath" : "sparkles"
            )
            .font(.montserrat(.subheadline, .semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// One counter, as its own card.
///
/// The label sits on its own line under the number rather than beside the
/// icon: "Correspondances" is fifteen characters and needs the full width of
/// the tile, which a label squeezed in next to the glyph does not have.
private struct StatTile: View {
    let label: String
    let value: Int
    let systemImage: String
    let tint: Color

    /// Optional: the screen that explains this number.
    var route: AppRoute?

    var body: some View {
        if let route {
            NavigationLink(value: route) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
            }
            Text(value, format: .number.locale(Locale(identifier: "fr_FR")))
                .font(.montserrat(.title2, .bold).monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.montserrat(.footnote, .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct ShortcutRow: View {
    let route: AppRoute
    let systemImage: String
    let label: String
    let tint: Color

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(label).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.montserrat(.footnote, .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One saved criterion: what it selects, how many members it matches, and the
/// two things you can do with it. The count sits by the label because it is
/// what the member checks before deciding to run the sync at all.
private struct CriteriaCard: View {
    let criteria: SyncCriteria

    var body: some View {
        let bits = criteria.countries.map(FilterOptions.countryLabel) + criteria.cities + criteria.professions + criteria.interests
        let desc = bits.isEmpty ? "Tous les membres" : bits.prefix(4).joined(separator: " · ")
        let more = bits.count > 4 ? " +\(bits.count - 4)" : ""

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(criteria.label)
                    .font(.montserrat(.headline))
                    .lineLimit(1)
                Spacer()
                Label("\(criteria.lastMatchCount)", systemImage: "person.2.fill")
                    .font(.montserrat(.caption, .bold))
                    .foregroundStyle(SBCColors.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(SBCColors.primary.opacity(0.1), in: Capsule())
                    .accessibilityLabel("\(criteria.lastMatchCount) correspondances")
            }
            Text(desc + more)
                .font(.montserrat(.subheadline))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Spacer()
                NavigationLink(value: AppRoute.criteriaEdit(criteria)) {
                    Label("Modifier", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                NavigationLink(value: AppRoute.syncReview(criteriaId: criteria.id, label: criteria.label)) {
                    Label("Synchroniser", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .padding(.top, 6)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
