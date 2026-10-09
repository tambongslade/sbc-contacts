import SwiftUI

/// The messages between a requester and one pro, oldest first. `me` decides
/// which side is "mine" (right, brand blue).
struct ConversationThread: View {
    let messages: [ConversationMessage]
    let me: ConversationMessage.Author
    /// Names for the other side's bubbles ("Aïcha M.", "Le client").
    let otherName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(messages) { message in
                let mine = message.author == me
                VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                    Text(message.text)
                        .font(.sbc(.bodyMedium))
                        .foregroundStyle(mine ? .white : SBCColors.onSurface)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(mine ? SBCColors.primary : SBCColors.background)
                        )
                    Text("\(mine ? "Toi" : otherName) · \(message.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.sbc(.labelSmall))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A short message sheet: answer a question or write to the other side.
struct MessageComposer: View {
    let title: String
    let placeholder: String
    var hint: String?
    /// Returns true once sent, which closes the sheet.
    let onSend: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $text, axis: .vertical).lineLimit(3...8)
                } footer: {
                    if let hint { Text(hint) }
                }
            }
            .font(.sbc(.bodyLarge))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer") {
                        Task {
                            sending = true
                            let ok = await onSend(text.trimmingCharacters(in: .whitespacesAndNewlines))
                            sending = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(text.nilIfBlank == nil || sending)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
