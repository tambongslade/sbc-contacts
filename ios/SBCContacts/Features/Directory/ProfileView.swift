import SwiftUI
import Observation

@MainActor
@Observable
final class ProfileStore {
    enum MemberState {
        case loading
        case loaded(Member)
        case failed(Error)
    }

    enum ReviewsState {
        case loading
        case loaded(MemberReviews)
        case failed
    }

    let sbcId: String
    private(set) var member: MemberState = .loading
    private(set) var reviews: ReviewsState = .loading

    private let directory: DirectoryRepository
    private let reviewsRepo: ReviewsRepository

    init(sbcId: String, services: AppServices) {
        self.sbcId = sbcId
        directory = services.directory
        reviewsRepo = services.reviews
    }

    var myReview: Review? {
        if case let .loaded(r) = reviews { return r.myReview }
        return nil
    }

    func load() async {
        async let m: Void = loadMember()
        async let r: Void = loadReviews()
        _ = await (m, r)
    }

    /// Create or update the caller's review, then refresh the list and the
    /// profile (so the score card updates in place).
    func submitReview(stars: Int, comment: String?) async throws {
        try await reviewsRepo.submit(memberSbcId: sbcId, stars: stars, comment: comment)
        await load()
    }

    func deleteReview() async {
        _ = try? await reviewsRepo.remove(memberSbcId: sbcId)
        await load()
    }

    private func loadMember() async {
        do {
            member = .loaded(try await directory.profile(sbcId: sbcId))
        } catch {
            if case .loaded = member { return } // keep what we have on a refresh failure
            member = .failed(error)
        }
    }

    private func loadReviews() async {
        do {
            reviews = .loaded(try await reviewsRepo.list(memberSbcId: sbcId))
        } catch {
            reviews = .failed
        }
    }
}

struct ProfileView: View {
    let sbcId: String

    @Environment(\.services) private var services
    @State private var store: ProfileStore?

    var body: some View {
        Group {
            if let store {
                ProfileContent(store: store)
            } else {
                ListSkeleton()
            }
        }
        .background(SBCColors.background)
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil {
                let s = ProfileStore(sbcId: sbcId, services: services)
                store = s
                await s.load()
            }
        }
    }
}

private struct ProfileContent: View {
    let store: ProfileStore

    var body: some View {
        switch store.member {
        case .loading:
            ListSkeleton()
        case let .failed(error):
            EmptyStateView(systemImage: "person.slash", title: "Profil indisponible", message: error.localizedDescription)
        case let .loaded(member):
            ProfileBody(member: member, store: store)
        }
    }
}

private struct ProfileBody: View {
    let member: Member
    let store: ProfileStore

    @Environment(AuthStore.self) private var auth
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.services) private var services
    @Environment(DirectoryStore.self) private var directory
    @Environment(SyncStore.self) private var sync
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 2) {
                    MemberAvatar(initials: member.initials, avatarUrl: member.avatarUrl, radius: 48)
                        .padding(.bottom, 14)
                    Text(member.displayName)
                        .font(.sbc(.headlineSmall, weight: .heavy))
                        .foregroundStyle(SBCColors.onSurface)
                        .multilineTextAlignment(.center)
                    if let profession = member.profession {
                        Text(profession)
                            .font(.sbc(.titleMedium))
                            .foregroundStyle(SBCColors.onSurface)
                            .multilineTextAlignment(.center)
                    }
                    if !member.location.isEmpty {
                        Text(member.location)
                            .font(.sbc(.bodyMedium))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity)

                ConfidenceScoreCard(score: member.confidenceScore, reviewCount: member.reviewCount)
                    .padding(.top, 20)

                HStack(spacing: 12) {
                    Button {
                        if let phone = member.phoneNumber {
                            openWhatsApp(phone, contactName: member.displayName)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            WhatsAppGlyph().frame(width: 18, height: 18)
                            Text("WhatsApp")
                        }
                    }
                    .buttonStyle(FilledButtonStyle(background: SBCColors.whatsapp, minHeight: 48))
                    .disabled(member.phoneNumber == nil)

                    Button {
                        Task {
                            adding = true
                            await addMemberToPhone(member, services: services, toasts: toasts, directory: directory, sync: sync)
                            adding = false
                        }
                    } label: {
                        if adding {
                            ProgressView()
                        } else {
                            Label("Ajouter", systemImage: "person.badge.plus")
                        }
                    }
                    .buttonStyle(OutlinedButtonStyle(minHeight: 48))
                    .disabled(adding)
                }
                .padding(.top, 24)

                ReviewsSection(
                    member: member,
                    store: store,
                    isOwnProfile: auth.user?.sbcUserId == member.sbcId
                )
                .padding(.top, 24)

                if !member.skills.isEmpty {
                    Text("Compétences")
                        .font(.sbc(.titleMedium))
                        .padding(.top, 24)
                    FlowLayout(spacing: 8, runSpacing: 6) {
                        ForEach(member.skills, id: \.self) { TagChip(label: $0) }
                    }
                    .padding(.top, 8)
                }
                if !member.interests.isEmpty {
                    Text("Centres d'intérêt")
                        .font(.sbc(.titleMedium))
                        .padding(.top, member.skills.isEmpty ? 24 : 16)
                    FlowLayout(spacing: 8, runSpacing: 6) {
                        ForEach(member.interests, id: \.self) { TagChip(label: $0) }
                    }
                    .padding(.top, 8)
                }
            }
            .foregroundStyle(SBCColors.onSurface)
            .padding(20)
        }
        .refreshable { await store.load() }
    }
}
