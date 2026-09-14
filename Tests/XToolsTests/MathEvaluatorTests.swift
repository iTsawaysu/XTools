import XToolsCore
import Testing

struct MathEvaluatorTests {
    @Test func exponentiationIsRightAssociative() throws {
        let result = try MathExpressionEvaluator.evaluate("2^3^2")
        #expect(result == "512")
    }

    @Test func exponentiationBindsBeforeUnaryMinus() throws {
        let result = try MathExpressionEvaluator.evaluate("-2^2")
        #expect(result == "-4")
    }

    @Test func basicArithmetic() throws {
        #expect(try MathExpressionEvaluator.evaluate("2 + 3") == "5")
        #expect(try MathExpressionEvaluator.evaluate("10 - 7") == "3")
        #expect(try MathExpressionEvaluator.evaluate("4 * 5") == "20")
        #expect(try MathExpressionEvaluator.evaluate("20 / 4") == "5")
        #expect(try MathExpressionEvaluator.evaluate("10 % 3") == "1")
    }

    @Test func operatorPrecedence() throws {
        #expect(try MathExpressionEvaluator.evaluate("2 + 3 * 4") == "14") // multiplication before addition
        #expect(try MathExpressionEvaluator.evaluate("10 - 6 / 2") == "7") // division before subtraction
        #expect(try MathExpressionEvaluator.evaluate("2 * 3 + 4 * 5") == "26") // left-to-right for same precedence
        #expect(try MathExpressionEvaluator.evaluate("2 ^ 3 * 4") == "32") // power before multiplication
    }

    @Test func parentheses() throws {
        #expect(try MathExpressionEvaluator.evaluate("(2 + 3) * 4") == "20") // override precedence
        #expect(try MathExpressionEvaluator.evaluate("((2 + 3) * 4)") == "20") // nested parentheses
        #expect(try MathExpressionEvaluator.evaluate("2 * (3 + 4)") == "14") // right-side parentheses
    }

    @Test func divisionByZero() throws {
        #expect(throws: (any Error).self) {
            _ = try MathExpressionEvaluator.evaluate("10 / 0")
        }
    }

    @Test func functions() throws {
        let sqrtResult = try MathExpressionEvaluator.evaluate("sqrt(16)")
        #expect(sqrtResult == "4")

        let absResult = try MathExpressionEvaluator.evaluate("abs(-5)")
        #expect(absResult == "5")

        let maxResult = try MathExpressionEvaluator.evaluate("max(3, 7)")
        #expect(maxResult == "7")

        let minResult = try MathExpressionEvaluator.evaluate("min(3, 7)")
        #expect(minResult == "3")
    }

    @Test func constants() throws {
        let piResult = try MathExpressionEvaluator.evaluate("pi * 2")
        #expect(piResult.hasPrefix("6.28"))

        let eResult = try MathExpressionEvaluator.evaluate("e")
        #expect(eResult.hasPrefix("2.71"))
    }

    @Test func emptyExpression() throws {
        #expect(throws: (any Error).self) {
            _ = try MathExpressionEvaluator.evaluate("")
        }

        #expect(throws: (any Error).self) {
            _ = try MathExpressionEvaluator.evaluate("   ")
        }
    }

    @Test func invalidSyntax() throws {
        // Note: "2 ++ 3" is parsed as "2 + (+3)" which is valid, so we test other invalid cases
        #expect(throws: (any Error).self) {
            _ = try MathExpressionEvaluator.evaluate("foo(5)")
        }

        #expect(throws: (any Error).self) {
            _ = try MathExpressionEvaluator.evaluate("(2 + 3")
        }

        #expect(throws: (any Error).self) {
            _ = try MathExpressionEvaluator.evaluate("2 @ 3")
        }
    }

    @Test func liveInputTreatsPartialExpressionsAsIncomplete() {
        #expect(MathExpressionEvaluator.evaluateLiveInput("") == .empty)
        #expect(MathExpressionEvaluator.evaluateLiveInput("1+") == .incomplete)
        #expect(MathExpressionEvaluator.evaluateLiveInput("1/") == .incomplete)
        #expect(MathExpressionEvaluator.evaluateLiveInput("1+2+") == .incomplete)
        #expect(MathExpressionEvaluator.evaluateLiveInput("1+2+3+") == .incomplete)
        #expect(MathExpressionEvaluator.evaluateLiveInput("(2 + 3") == .incomplete)
        #expect(MathExpressionEvaluator.evaluateLiveInput("sqrt(") == .incomplete)
        #expect(MathExpressionEvaluator.evaluateLiveInput("max(1,") == .incomplete)
        #expect(MathExpressionEvaluator.evaluateLiveInput("sq") == .incomplete)
        #expect(MathExpressionEvaluator.evaluateLiveInput("1e") == .incomplete)
        #expect(MathExpressionEvaluator.evaluateLiveInput("1e-") == .incomplete)
        #expect(MathExpressionEvaluator.evaluateLiveInput("1e+") == .incomplete)
    }

    @Test func liveInputStillSeparatesValidAndInvalidExpressions() {
        #expect(MathExpressionEvaluator.evaluateLiveInput("1+2+3+4") == .valid("10"))
        #expect(MathExpressionEvaluator.evaluateLiveInput("2 @ 3") == .invalid(.unexpectedCharacter("@")))
        #expect(MathExpressionEvaluator.evaluateLiveInput("1 / 0") == .invalid(.divisionByZero))
        #expect(MathExpressionEvaluator.evaluateLiveInput("foo") == .invalid(.unknownIdentifier("foo")))
    }

    @Test func liveInputRejectsMalformedOperatorRunsInsteadOfStayingQuiet() {
        #expect(MathExpressionEvaluator.evaluateLiveInput("///") == .invalid(.unexpectedToken))
        #expect(MathExpressionEvaluator.evaluateLiveInput("1//") == .invalid(.unexpectedToken))
        #expect(MathExpressionEvaluator.evaluateLiveInput("1**") == .invalid(.unexpectedToken))
        #expect(MathExpressionEvaluator.evaluateLiveInput("1+*") == .invalid(.unexpectedToken))
        #expect(MathExpressionEvaluator.evaluateLiveInput("1,") == .invalid(.unexpectedToken))
    }

    @Test func everyMathErrorUsesSpecificFactualChineseCopy() {
        let errors: [MathExpressionEvaluator.MathError] = [
            .unexpectedCharacter("@"),
            .invalidNumber("1e++2"),
            .unknownIdentifier("privateSecretIdentifier"),
            .unexpectedToken,
            .unexpectedEnd,
            .divisionByZero,
            .mismatchedParentheses,
            .emptyExpression,
            .wrongArgumentCount("sqrt", 1),
            .minimumArgumentCount("max", 2),
            .domainError(.nonNegative("sqrt")),
            .domainError(.unitInterval("asin")),
            .domainError(.positive("log")),
            .nonFiniteResult
        ]

        for error in errors {
            ToolDiagnosticContract.expectFactual(
                error.errorDescription ?? "",
                sensitiveInputs: ["privateSecretIdentifier"]
            )
        }
    }

    @Test func pastedTerminalLogDoesNotBecomeTheMathDiagnostic() {
        let terminalLog = "Ran osascript -e System Events /tmp/capture.mov execution error"
        guard case .invalid(let error) = MathExpressionEvaluator.evaluateLiveInput(terminalLog) else {
            Issue.record("expected invalid math expression")
            return
        }
        ToolDiagnosticContract.expectFactual(
            error.errorDescription ?? "",
            sensitiveInputs: [terminalLog]
        )
    }

    // MARK: - Decimal formatting (silent-miscalculation risk)

    @Test func nonIntegerResultsKeepUsefulSignificantDigits() throws {
        #expect(try MathExpressionEvaluator.evaluate("1 / 4") == "0.25")
        #expect(try MathExpressionEvaluator.evaluate("10 / 3") == "3.33333333333333")
        #expect(try MathExpressionEvaluator.evaluate("7 / 2") == "3.5")
        #expect(try MathExpressionEvaluator.evaluate("0.1 + 0.2") == "0.3")
    }

    @Test func integerValuedResultsRenderWithoutDecimalPoint() throws {
        // A float that lands exactly on an integer must not print "6.0".
        #expect(try MathExpressionEvaluator.evaluate("3 * 2.0") == "6")
        #expect(try MathExpressionEvaluator.evaluate("sqrt(9)") == "3")
    }

    @Test func nonIntegerResultsUseFifteenSignificantDigits() throws {
        let result = try MathExpressionEvaluator.evaluate("pi")
        #expect(result == "3.14159265358979")
    }

    @Test func smallNonzeroResultsNeverFormatAsZero() throws {
        #expect(try MathExpressionEvaluator.evaluate("1e-9") == "0.000000001")
        #expect(try MathExpressionEvaluator.evaluate("1e-10") == "1e-10")
        #expect(try MathExpressionEvaluator.evaluate("1e-11") == "1e-11")
        #expect(try MathExpressionEvaluator.evaluate("1e-12") == "1e-12")
        #expect(try MathExpressionEvaluator.evaluate("-1e-12") == "-1e-12")
    }

    @Test func extremeMagnitudesUseCompactScientificNotation() throws {
        #expect(try MathExpressionEvaluator.evaluate("1e15") == "1000000000000000")
        #expect(try MathExpressionEvaluator.evaluate("1e16") == "1e+16")
        #expect(try MathExpressionEvaluator.evaluate("1.234567890123456e20") == "1.23456789012346e+20")
    }

    @Test func negativeZeroIsNormalized() throws {
        #expect(try MathExpressionEvaluator.evaluate("-0") == "0")
    }

    @Test func scientificNotationNumbersAreSupported() throws {
        #expect(try MathExpressionEvaluator.evaluate("1e3 + 2.5e-1") == "1000.25")
        #expect(try MathExpressionEvaluator.evaluate("2E3 / 4") == "500")
        #expect(try MathExpressionEvaluator.evaluate(".5e2") == "50")
    }

    @Test func invalidScientificNotationThrowsInvalidNumber() throws {
        #expect(throws: MathExpressionEvaluator.MathError.invalidNumber("1e")) {
            _ = try MathExpressionEvaluator.evaluate("1e + 2")
        }
    }

    @Test func formattedOutputDoesNotUseGroupingSeparators() throws {
        #expect(try MathExpressionEvaluator.evaluate("1000 + 0.5") == "1000.5")
    }

    // MARK: - Modulo and power edge cases

    @Test func moduloByZeroThrows() throws {
        #expect(throws: MathExpressionEvaluator.MathError.divisionByZero) {
            _ = try MathExpressionEvaluator.evaluate("5 % 0")
        }
    }

    @Test func negativeExponentProducesReciprocal() throws {
        #expect(try MathExpressionEvaluator.evaluate("2 ^ -1") == "0.5")
        #expect(try MathExpressionEvaluator.evaluate("2 ^ -2") == "0.25")
    }

    @Test func fractionalExponentTakesRoot() throws {
        #expect(try MathExpressionEvaluator.evaluate("9 ^ 0.5") == "3")
    }

    // MARK: - Domain errors (wrong answer would be silently wrong)

    @Test func sqrtOfNegativeThrowsDomainError() throws {
        expectDomainError { try MathExpressionEvaluator.evaluate("sqrt(-1)") }
    }

    @Test func logOfNonPositiveThrowsDomainError() throws {
        expectDomainError { try MathExpressionEvaluator.evaluate("log(0)") }
        expectDomainError { try MathExpressionEvaluator.evaluate("ln(-2)") }
    }

    @Test func inverseTrigOutsideDomainThrows() throws {
        expectDomainError { try MathExpressionEvaluator.evaluate("asin(2)") }
        expectDomainError { try MathExpressionEvaluator.evaluate("acos(-3)") }
    }

    @Test func nonFiniteResultThrows() throws {
        // An exponentiation that overflows Double to +inf must be rejected as a
        // non-finite result, never returned as a bogus finite string.
        #expect(throws: MathExpressionEvaluator.MathError.nonFiniteResult) {
            _ = try MathExpressionEvaluator.evaluate("10 ^ 400")
        }
    }

    // MARK: - Additional functions and constants

    @Test func roundingFunctions() throws {
        #expect(try MathExpressionEvaluator.evaluate("floor(3.7)") == "3")
        #expect(try MathExpressionEvaluator.evaluate("ceil(3.2)") == "4")
        #expect(try MathExpressionEvaluator.evaluate("round(3.5)") == "4")
        #expect(try MathExpressionEvaluator.evaluate("round(2.4)") == "2")
    }

    @Test func exponentialAndCubeRoot() throws {
        #expect(try MathExpressionEvaluator.evaluate("cbrt(27)") == "3")

        let expResult = try MathExpressionEvaluator.evaluate("exp(0)")
        #expect(expResult == "1")
    }

    @Test func trigFunctionsUseRadians() throws {
        // sin(pi/2) = 1, cos(0) = 1 — confirms radian interpretation.
        let sinResult = try MathExpressionEvaluator.evaluate("sin(pi / 2)")
        #expect(sinResult == "1")

        let cosResult = try MathExpressionEvaluator.evaluate("cos(0)")
        #expect(cosResult == "1")
    }

    @Test func goldenRatioConstant() throws {
        let result = try MathExpressionEvaluator.evaluate("phi")
        #expect(result.hasPrefix("1.618"))
    }

    @Test func minAndMaxRequireAtLeastTwoArguments() throws {
        expectMinimumArgumentCount { try MathExpressionEvaluator.evaluate("max(5)") }
        expectMinimumArgumentCount { try MathExpressionEvaluator.evaluate("min(5)") }
    }

    @Test func singleArgumentFunctionRejectsExtraArguments() throws {
        expectWrongArgumentCount { try MathExpressionEvaluator.evaluate("sqrt(4, 9)") }
    }
}

// MARK: - Error-shape helpers

extension MathEvaluatorTests {
    /// Assert the expression throws `MathError.domainError` specifically. Domain
    /// errors carry an associated message, so they can't be passed as a `throws:`
    /// value directly — match the case in a closure. Using the concrete case (not
    /// `any Error`) stops a silent regression where a domain violation degrades
    /// into a different error kind (e.g. `sqrt(-1)` slipping through to the
    /// non-finite guard) from passing unnoticed.
    private func expectDomainError(
        _ expression: () throws -> String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(sourceLocation: sourceLocation) {
            _ = try expression()
        } throws: { error in
            guard case MathExpressionEvaluator.MathError.domainError = error else { return false }
            return true
        }
    }

    /// Assert the expression throws `MathError.wrongArgumentCount` specifically
    /// (associated values, so matched in a closure).
    private func expectWrongArgumentCount(
        _ expression: () throws -> String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(sourceLocation: sourceLocation) {
            _ = try expression()
        } throws: { error in
            guard case MathExpressionEvaluator.MathError.wrongArgumentCount = error else { return false }
            return true
        }
    }

    private func expectMinimumArgumentCount(
        _ expression: () throws -> String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(sourceLocation: sourceLocation) {
            _ = try expression()
        } throws: { error in
            guard case MathExpressionEvaluator.MathError.minimumArgumentCount = error else { return false }
            return true
        }
    }
}
