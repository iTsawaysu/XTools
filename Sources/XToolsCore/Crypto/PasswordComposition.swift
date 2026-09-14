import Foundation

public enum PasswordComposition {
    public static func characterSet(
        lower: Bool,
        upper: Bool,
        numbers: Bool,
        symbols: Bool,
        excludeAmbiguous: Bool
    ) -> String {
        enabledCharacterSets(
            lower: lower,
            upper: upper,
            numbers: numbers,
            symbols: symbols,
            excludeAmbiguous: excludeAmbiguous
        ).joined()
    }

    public static func enabledCharacterSets(
        lower: Bool,
        upper: Bool,
        numbers: Bool,
        symbols: Bool,
        excludeAmbiguous: Bool
    ) -> [String] {
        var lowerChars = "abcdefghijklmnopqrstuvwxyz"
        var upperChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        var numberChars = "0123456789"
        let symbolChars = "!@#$%^&*()_+-=[]|;:,.<>?"

        if excludeAmbiguous {
            lowerChars = lowerChars.filter { !"lo".contains($0) }
            upperChars = upperChars.filter { !"IO".contains($0) }
            numberChars = numberChars.filter { !"01".contains($0) }
        }

        return [
            lower ? lowerChars : "",
            upper ? upperChars : "",
            numbers ? numberChars : "",
            symbols ? symbolChars : ""
        ].filter { !$0.isEmpty }
    }

}
