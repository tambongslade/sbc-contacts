import SwiftUI
import UIKit

/// The message WhatsApp opens pre-filled when a member is contacted from the
/// app (cahier §8).
///
/// Pre-filled, never sent: `wa.me?text=` only puts the text in the composer, so
/// the member still reads it and presses send. That is the whole reason this is
/// a deep link and not an API call.
///
/// The name is addressed as SBC gives it; a member with no name on file gets
/// the greeting without one rather than "Salut ".
func whatsAppGreeting(for contactName: String?) -> String {
    let name = contactName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let salutation = name.isEmpty ? "Salut" : "Salut \(name)"
    return "\(salutation), je vous contacte à partir de l'application SBC network."
}

/// Opens a WhatsApp conversation via the public `wa.me` link (cahier §8). The
/// app never sends messages automatically and never controls WhatsApp — it
/// only hands off to it.
///
/// `contactName` fills in the standard greeting; pass `presetText` to override
/// it, or the empty string for an empty composer.
@MainActor
@discardableResult
func openWhatsApp(
    _ phoneNumber: String,
    contactName: String? = nil,
    presetText: String? = nil
) -> Bool {
    let digits = phoneNumber.filter(\.isNumber)
    guard !digits.isEmpty else { return false }
    var components = URLComponents(string: "https://wa.me/\(digits)")!
    let text = presetText ?? whatsAppGreeting(for: contactName)
    if !text.isEmpty { components.queryItems = [.init(name: "text", value: text)] }
    guard let url = components.url else { return false }
    UIApplication.shared.open(url)
    return true
}

/// "Contacter sur WhatsApp", as a filled brand-green disc with the real
/// WhatsApp glyph — a generic chat bubble doesn't tell the member which app is
/// about to open.
struct WhatsAppButton: View {
    let phoneNumber: String?

    /// Addressed in the pre-filled greeting, so the member does not have to
    /// type "Salut X" themselves every time.
    var contactName: String?
    var size: CGFloat = 40

    private var enabled: Bool {
        !(phoneNumber?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    var body: some View {
        Button {
            if let phoneNumber { openWhatsApp(phoneNumber, contactName: contactName) }
        } label: {
            ZStack {
                Circle().fill(enabled ? SBCColors.whatsapp : SBCColors.onSurfaceVariant.opacity(0.12))
                WhatsAppGlyph()
                    .foregroundStyle(enabled ? Color.white : SBCColors.onSurfaceVariant)
                    .frame(width: size * 0.55, height: size * 0.55)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Contacter sur WhatsApp")
        .accessibilityHint(enabled ? "" : "Numéro non disponible")
    }
}

struct WhatsAppGlyph: View {
    var body: some View {
        Image("whatsapp")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }
}
