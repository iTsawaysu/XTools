@testable import XTools
import Testing

struct JWTLocalCheckDisclosureStateTests {
    @Test func startsCollapsedAndExistingSecretExpandsOnlyBeforeUserChoice() {
        var state = JWTLocalCheckDisclosureState()
        #expect(!state.isExpanded)

        state.prepare(hasSecret: true, hasPresentation: false, issueID: nil)
        #expect(state.isExpanded)

        state.userToggle()
        #expect(!state.isExpanded)

        state.secretChanged(isEmpty: false)
        state.prepare(hasSecret: true, hasPresentation: false, issueID: nil)
        #expect(!state.isExpanded)
    }

    @Test func sameIssueDoesNotReopenAfterManualCollapse() {
        var state = JWTLocalCheckDisclosureState()

        state.presentationChanged(isPresent: true, issueID: "signature-failed")
        #expect(state.isExpanded)

        state.userToggle()
        #expect(!state.isExpanded)

        state.presentationChanged(isPresent: true, issueID: "signature-failed")
        #expect(!state.isExpanded)
    }

    @Test func resolvedThenRecurringIssueMayExpandAgain() {
        var state = JWTLocalCheckDisclosureState()
        state.presentationChanged(isPresent: true, issueID: "expired")
        state.userToggle()
        #expect(!state.isExpanded)

        state.presentationChanged(isPresent: true, issueID: nil)
        state.presentationChanged(isPresent: true, issueID: "expired")

        #expect(state.isExpanded)
    }

    @Test func explicitTransferAndResetOwnDeterministicVisibility() {
        var state = JWTLocalCheckDisclosureState()
        state.presentationChanged(isPresent: true, issueID: "warning")
        state.userToggle()
        #expect(!state.isExpanded)

        state.revealForExplicitTransfer(issueID: "warning")
        #expect(state.isExpanded)

        state.reset()
        #expect(!state.isExpanded)
        state.secretChanged(isEmpty: false)
        #expect(state.isExpanded)
    }
}
