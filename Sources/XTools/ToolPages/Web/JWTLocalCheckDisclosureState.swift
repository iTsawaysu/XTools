import Foundation

struct JWTLocalCheckDisclosureState: Equatable {
    private(set) var isExpanded = false
    private var hasUserControlledExpansion = false
    private var lastAutoExpandedIssueID: String?

    mutating func userToggle() {
        hasUserControlledExpansion = true
        isExpanded.toggle()
    }

    mutating func prepare(
        hasSecret: Bool,
        hasPresentation: Bool,
        issueID: String?
    ) {
        if hasSecret, !hasUserControlledExpansion {
            isExpanded = true
        }
        presentationChanged(isPresent: hasPresentation, issueID: issueID)
    }

    mutating func secretChanged(isEmpty: Bool) {
        guard !isEmpty, !hasUserControlledExpansion else { return }
        isExpanded = true
    }

    mutating func presentationChanged(isPresent: Bool, issueID: String?) {
        guard let issueID else {
            if isPresent {
                lastAutoExpandedIssueID = nil
            }
            return
        }
        guard issueID != lastAutoExpandedIssueID else { return }
        lastAutoExpandedIssueID = issueID
        isExpanded = true
    }

    mutating func revealForExplicitTransfer(issueID: String?) {
        hasUserControlledExpansion = false
        lastAutoExpandedIssueID = issueID
        isExpanded = true
    }

    mutating func reveal() {
        isExpanded = true
    }

    mutating func reset() {
        self = JWTLocalCheckDisclosureState()
    }
}
