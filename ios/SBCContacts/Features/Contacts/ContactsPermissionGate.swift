import SwiftUI
import UIKit

/// Asks for contacts access when the app opens, explaining why first.
///
/// iOS only shows its system dialog once, so firing the raw request on launch
/// spends it on a member who has no idea what is being asked. This shows the
/// reason first (cahier §12, §13, §20), and once access is denied it points at
/// Settings, which is the only place left to grant it.
private struct ContactsPermissionGate: ViewModifier {
    @Environment(ToastCenter.self) private var toasts
    @State private var presented = false
    @State private var blocked = false
    @State private var checked = false

    private let service = ContactService()

    func body(content: Content) -> some View {
        content
            .task {
                guard !checked else { return }
                checked = true
                switch service.checkPermission() {
                case .granted: return // already usable — never nag
                case .notDetermined: blocked = false
                case .denied: blocked = true
                }
                presented = true
            }
            .alert("Accès à vos contacts", isPresented: $presented) {
                Button("Plus tard", role: .cancel) {}
                Button(blocked ? "Ouvrir les paramètres" : "Autoriser") {
                    Task { await accept() }
                }
            } message: {
                Text("""
                SBC Network a besoin de votre carnet de contacts pour :
                • enregistrer les membres SBC que vous choisissez
                • synchroniser ceux qui correspondent à vos critères
                • éviter les doublons avant de créer une fiche

                \(blocked
                    ? "L'accès a été refusé. Vous pouvez l'activer dans les paramètres du téléphone."
                    : "Rien n'est ajouté sans votre confirmation, et aucun message n'est envoyé automatiquement.")
                """)
            }
    }

    private func accept() async {
        if blocked {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return
        }
        if await !service.requestPermission() {
            toasts.show("Sans cet accès, l'ajout au téléphone et la synchronisation resteront indisponibles.")
        }
    }
}

extension View {
    func contactsPermissionGate() -> some View { modifier(ContactsPermissionGate()) }
}

/// Adds a member to the phone contacts (cahier §9), then records it so it
/// shows up in "Mes contacts SBC" (§16).
///
/// The recording step is not optional bookkeeping: that screen lists what the
/// backend knows, so a contact saved here and never reported is one the member
/// cannot find again in the app.
@MainActor
func addMemberToPhone(
    _ member: Member,
    services: AppServices,
    toasts: ToastCenter,
    directory: DirectoryStore?,
    sync: SyncStore?
) async {
    let service = ContactService()
    guard await service.requestPermission() else {
        toasts.show("Permission contacts refusée")
        return
    }

    func record(deviceContactId: String?) async -> Bool {
        do {
            let recorded = try await services.sync.recordSingleContact(
                memberSbcId: member.sbcId,
                deviceContactId: deviceContactId
            )
            guard recorded else { return false }
        } catch {
            return false
        }
        directory?.setSyncedLocal(sbcId: member.sbcId)
        await sync?.loadSummary()
        return true
    }

    // Already on the device: nothing to write, but it still belongs in the
    // list — that screen reports on what is in the phone book, and it is.
    if let phone = member.phoneNumber, await service.existsByPhone(phone) {
        _ = await record(deviceContactId: nil)
        toasts.show("Déjà dans ton répertoire")
        return
    }

    let result = await service.addSBCContact(
        displayName: member.displayName,
        phone: member.phoneNumber,
        profession: member.profession
    )
    guard result.success else {
        toasts.show("Échec: \(result.error ?? "")")
        return
    }
    let recorded = await record(deviceContactId: result.deviceContactId)
    // Say which half failed: the contact IS on the phone, and calling it a
    // failure outright would send the member to save it twice.
    toasts.show(recorded
        ? "Contact ajouté — visible dans « Mes contacts SBC »"
        : "Contact ajouté au téléphone (pas encore synchronisé au serveur)")
}
