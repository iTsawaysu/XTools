public enum ConverterModeBackfill {
    public static func currentValidOutput(
        input: String,
        currentMode: String,
        hasError: Bool,
        isEmptyInput: (String) -> Bool = { $0.isEmpty },
        convert: (String, String) throws -> String
    ) -> String? {
        guard !hasError, !isEmptyInput(input) else {
            return nil
        }

        guard let output = try? convert(input, currentMode), !output.isEmpty else {
            return nil
        }

        return output
    }
}
