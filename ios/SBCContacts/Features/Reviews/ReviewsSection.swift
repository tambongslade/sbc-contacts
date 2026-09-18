import SwiftUI

/// The reviews block on a member profile: heading + "leave a review" action
/// (hidden on your own profile) + the list of reviews.
struct ReviewsSection: View {
    let member: Member
    let store: ProfileStore
    let isOwnProfile: Bool

    @State private var showForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Avis").font(.sbc(.titleMedium))
                Spacer()
                if !isOwnProfile {
                    Button { showForm = true } label: {
                        Label(store.myReview == nil ? "Laisser un avis" : "Modifier",
                              systemImage: store.myReview == nil ? "text.bubble" : "pencil")
                    }
                    .buttonStyle(.text)
                }
            }

            switch store.reviews {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            case .failed:
                muted("Avis indisponibles")
            case let .loaded(data) where data.reviews.isEmpty:
                muted("Aucun avis pour le moment.")
            case let .loaded(data):
                ForEach(data.reviews) { review in
                    ReviewRow(review: review) {
                        Task { await store.deleteReview() }
                    }
                }
            }
        }
        .sheet(isPresented: $showForm) {
            ReviewFormSheet(memberName: member.displayName, existing: store.myReview) { stars, comment in
                try await store.submitReview(stars: stars, comment: comment)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func muted(_ text: String) -> some View {
        Text(text)
            .font(.sbc(.bodyMedium))
            .foregroundStyle(SBCColors.onSurfaceVariant)
    }
}

private struct ReviewRow: View {
    let review: Review
    let onDelete: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MemberAvatar(initials: review.reviewerInitials, avatarUrl: review.reviewerAvatarUrl, radius: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(review.isMine ? "Vous" : review.reviewerDisplayName)
                        .font(.sbc(.titleSmall, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    StarRatingDisplay(value: Double(review.stars), size: 15)
                }
                if let comment = review.comment, !comment.isEmpty {
                    Text(comment).font(.sbc(.bodyMedium))
                }
            }
            if review.isMine {
                Button { confirmDelete = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Supprimer mon avis")
                .confirmationDialog("Supprimer mon avis ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Supprimer", role: .destructive, action: onDelete)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

/// Sheet to create or edit the caller's review, pre-filled when editing.
private struct ReviewFormSheet: View {
    let memberName: String
    let existing: Review?
    let submit: (Int, String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @State private var stars: Int
    @State private var comment: String
    @State private var submitting = false

    init(memberName: String, existing: Review?, submit: @escaping (Int, String?) async throws -> Void) {
        self.memberName = memberName
        self.existing = existing
        self.submit = submit
        _stars = State(initialValue: existing?.stars ?? 0)
        _comment = State(initialValue: existing?.comment ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text(existing == nil ? "Laisser un avis" : "Modifier mon avis")
                        .font(.sbc(.titleLarge, weight: .heavy))
                    Text(memberName)
                        .font(.sbc(.bodyMedium))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                }
                .multilineTextAlignment(.center)

                StarRatingInput(value: $stars)

                VStack(alignment: .trailing, spacing: 4) {
                    ZStack(alignment: .topLeading) {
                        if comment.isEmpty {
                            Text("Comment s'est passé le business ? (facultatif)")
                                .font(.sbc(.bodyLarge))
                                .foregroundStyle(SBCColors.onSurfaceVariant)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                        TextEditor(text: $comment)
                            .font(.sbc(.bodyLarge))
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .frame(minHeight: 96, maxHeight: 160)
                            .onChange(of: comment) { _, new in
                                if new.count > 2000 { comment = String(new.prefix(2000)) }
                            }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(SBCColors.outlineVariant))
                    .accessibilityLabel("Votre avis (facultatif)")
                    Text("\(comment.count)/2000")
                        .font(.sbc(.bodySmall))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                }

                Button {
                    Task { await send() }
                } label: {
                    if submitting {
                        ProgressView().tint(.white)
                    } else {
                        Text(existing == nil ? "Publier" : "Mettre à jour")
                    }
                }
                .buttonStyle(FilledButtonStyle(minHeight: 48))
                .disabled(stars < 1 || submitting)
            }
            .padding(EdgeInsets(top: 28, leading: 20, bottom: 20, trailing: 20))
        }
        .background(SBCColors.surface)
    }

    private func send() async {
        submitting = true
        do {
            try await submit(stars, comment.trimmed)
            dismiss()
            toasts.show("Avis enregistré")
        } catch {
            submitting = false
            toasts.show("Échec: \(error.localizedDescription)")
        }
    }
}
