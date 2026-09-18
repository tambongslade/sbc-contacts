import SwiftUI

/// Pushed screens (the go_router routes other than the tabs).
enum AppRoute: Hashable {
    case profile(sbcId: String)
    case syncHistory
    case syncedContacts
    case savedMe
    case syncReview(criteriaId: String, label: String)
    case criteriaNew
    case criteriaEdit(SyncCriteria)
}

extension SyncCriteria: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension View {
    /// Registers every pushable screen on a tab's NavigationStack.
    func appRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case let .profile(sbcId):
                ProfileView(sbcId: sbcId)
            case .syncHistory:
                SyncHistoryView()
            case .syncedContacts:
                SyncedContactsView()
            case .savedMe:
                SavedMeView()
            case let .syncReview(criteriaId, label):
                SyncReviewView(criteriaId: criteriaId, label: label)
            case .criteriaNew:
                CriteriaEditView(existing: nil)
            case let .criteriaEdit(criteria):
                CriteriaEditView(existing: criteria)
            }
        }
    }
}
