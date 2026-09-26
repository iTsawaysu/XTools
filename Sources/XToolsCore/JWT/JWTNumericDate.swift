import CoreFoundation
import Foundation

/// JSONSerialization bridges both JSON numbers and booleans to NSNumber.
/// Check the Core Foundation type so numeric 0/1 remain valid NumericDates.
enum JWTNumericDate {
    static func timestamp(_ value: Any) -> TimeInterval? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }

        let timestamp = number.doubleValue
        return timestamp.isFinite ? timestamp : nil
    }
}
