import Contacts
import Foundation

/// Result of writing one member to the phone book.
struct ContactWriteResult: Sendable {
    let success: Bool
    var deviceContactId: String?
    var error: String?
}

/// Wraps the native Contacts framework. Contacts created by the app are tagged
/// with organisation "SBC" so they're identifiable for later synchronisation
/// and dedup (cahier §14/§15). No auto-messaging — ever.
struct ContactService: Sendable {
    enum Access: Sendable {
        case notDetermined, granted, denied
    }

    /// Current status without prompting — lets the UI explain itself before the
    /// system dialog appears, and stay quiet once access is granted.
    func checkPermission() -> Access {
        Self.map(CNContactStore.authorizationStatus(for: .contacts))
    }

    /// iOS 18 "limited" means the member picked specific contacts to share;
    /// that is still enough to create and dedup, so it counts as granted.
    private static func map(_ status: CNAuthorizationStatus) -> Access {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        default:
            if #available(iOS 18.0, *), status == .limited { return .granted }
            return .denied
        }
    }

    func requestPermission() async -> Bool {
        switch checkPermission() {
        case .granted: return true
        case .denied: return false
        case .notDetermined:
            _ = try? await CNContactStore().requestAccess(for: .contacts)
            return checkPermission() == .granted
        }
    }

    /// True if a contact with this phone number already exists on the device
    /// (cahier §15 duplicate detection — the authoritative check is native).
    func existsByPhone(_ phone: String) async -> Bool {
        let normalized = Self.digits(phone)
        guard !normalized.isEmpty else { return false }
        let request = CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey as CNKeyDescriptor])
        var found = false
        try? CNContactStore().enumerateContacts(with: request) { contact, stop in
            for number in contact.phoneNumbers {
                let d = Self.digits(number.value.stringValue)
                if !d.isEmpty, d.hasSuffix(normalized) || normalized.hasSuffix(d) {
                    found = true
                    stop.pointee = true
                    return
                }
            }
        }
        return found
    }

    /// Writes one member to the phone book.
    ///
    /// `displayName` is the member's whole name and the only name input: SBC
    /// puts the full name in `name` and often leaves `firstName` empty, so
    /// passing both wrote "Claude Durel Claude Durel". Splitting one string
    /// here is the only way the two halves cannot disagree.
    func addSBCContact(
        displayName: String,
        phone: String?,
        profession: String?
    ) async -> ContactWriteResult {
        let contact = CNMutableContact()
        let name = Self.nameParts(displayName)
        contact.givenName = name.given
        contact.familyName = name.family
        if let phone, !phone.isEmpty {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
        }
        contact.organizationName = "SBC"
        contact.jobTitle = profession ?? ""

        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        do {
            try CNContactStore().execute(request)
            return ContactWriteResult(success: true, deviceContactId: contact.identifier)
        } catch {
            return ContactWriteResult(success: false, error: error.localizedDescription)
        }
    }

    /// First word → given name, the rest → family name with "SBC" appended, so
    /// the phone's own list shows "Claude Durel SBC" and every contact the app
    /// wrote is recognisable without opening it. Idempotent on "… SBC".
    static func nameParts(_ displayName: String) -> (given: String, family: String) {
        let parts = displayName.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = parts.first else { return ("Membre", "SBC") }
        let rest = parts.dropFirst().joined(separator: " ")
        let family: String
        if rest.isEmpty {
            family = "SBC"
        } else if rest.uppercased().hasSuffix("SBC") {
            family = rest
        } else {
            family = "\(rest) SBC"
        }
        return (first, family)
    }

    private static func digits(_ s: String) -> String {
        s.filter(\.isNumber)
    }
}
