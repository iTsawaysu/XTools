@testable import XTools
@testable import XToolsCore
import Testing

struct ChmodCalculatorTests {
    @Test func parsesCommonModesAndCanonicalizesLeadingZero() throws {
        let none = try ChmodMode(octal: "000")
        #expect(none.octalString == "000")
        #expect(none.symbolicString == "---------")

        let standard = try ChmodMode(octal: "0644")
        #expect(standard.octalString == "644")
        #expect(standard.symbolicString == "rw-r--r--")

        let executable = try ChmodMode(octal: "755")
        #expect(executable.octalString == "755")
        #expect(executable.symbolicString == "rwxr-xr-x")
    }

    @Test func parsesAndRendersSpecialPermissionBits() throws {
        let setuid = try ChmodMode(octal: "4755")
        #expect(setuid.setuid)
        #expect(setuid.symbolicString == "rwsr-xr-x")

        let setgid = try ChmodMode(octal: "2750")
        #expect(setgid.setgid)
        #expect(setgid.symbolicString == "rwxr-s---")

        let sticky = try ChmodMode(octal: "1777")
        #expect(sticky.sticky)
        #expect(sticky.symbolicString == "rwxrwxrwt")
    }

    @Test func usesUppercaseSpecialSymbolsWhenExecuteIsCleared() throws {
        let mode = try ChmodMode(octal: "7644")
        #expect(mode.symbolicString == "rwSr-Sr-T")
    }

    @Test func rejectsInvalidLengthCharactersAndOctalDigits() {
        #expect(throws: ChmodMode.ParseError.invalidLength) {
            try ChmodMode(octal: "64")
        }
        #expect(throws: ChmodMode.ParseError.invalidLength) {
            try ChmodMode(octal: "06444")
        }
        #expect(throws: ChmodMode.ParseError.nonOctalDigit) {
            try ChmodMode(octal: "6a4")
        }
        #expect(throws: ChmodMode.ParseError.digitOutOfRange) {
            try ChmodMode(octal: "684")
        }
    }

    @MainActor
    @Test func workspaceSynchronizesOctalInputAndPermissionControlsAtomically() {
        let workspace = ChmodToolWorkspaceModel()
        #expect(workspace.octalDraft == "644")
        #expect(workspace.mode.symbolicString == "rw-r--r--")

        workspace.updateOctalDraft("4755")
        #expect(workspace.error == nil)
        #expect(workspace.mode.setuid)
        #expect(workspace.mode.owner.execute)
        #expect(workspace.octalDraft == "4755")

        workspace.set(false, for: \ChmodMode.owner.execute)
        #expect(workspace.octalDraft == "4655")
        #expect(workspace.mode.symbolicString == "rwSr-xr-x")

        let lastValidMode = workspace.mode
        let invalidDrafts = [
            ("48", "Chmod 八进制需要 3 位或 4 位数字。"),
            ("6a4", "Chmod 八进制只能包含数字。"),
            ("684", "Chmod 八进制每一位只能是 0–7。")
        ]
        for (draft, expectedMessage) in invalidDrafts {
            workspace.updateOctalDraft(draft)
            #expect(workspace.error == expectedMessage)
            #expect(workspace.mode == lastValidMode)
            #expect(workspace.octalDraft == draft)
            ToolDiagnosticContract.expectFactual(expectedMessage)
        }

        workspace.updateOctalDraft("1777")
        #expect(workspace.error == nil)
        #expect(workspace.mode.sticky)
        #expect(workspace.mode.symbolicString == "rwxrwxrwt")
    }
}
