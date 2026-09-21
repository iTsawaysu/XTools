import Foundation

public struct ChmodMode: Equatable, Sendable {
    public enum ParseError: Error, Equatable, Sendable, LocalizedError {
        case invalidLength
        case nonOctalDigit
        case digitOutOfRange

        public var errorDescription: String? {
            switch self {
            case .invalidLength:
                return "Chmod 八进制需要 3 位或 4 位数字。"
            case .nonOctalDigit:
                return "Chmod 八进制只能包含数字。"
            case .digitOutOfRange:
                return "Chmod 八进制每一位只能是 0–7。"
            }
        }
    }

    public struct PermissionTriad: Equatable, Sendable {
        public var read: Bool
        public var write: Bool
        public var execute: Bool

        public init(read: Bool, write: Bool, execute: Bool) {
            self.read = read
            self.write = write
            self.execute = execute
        }

        public var octalValue: Int {
            (read ? 4 : 0) + (write ? 2 : 0) + (execute ? 1 : 0)
        }

        fileprivate init(octalValue: Int) {
            read = octalValue & 4 != 0
            write = octalValue & 2 != 0
            execute = octalValue & 1 != 0
        }

        fileprivate func symbolic(special: Bool, lowercaseSpecial: Character) -> String {
            let executeSymbol: Character
            if special {
                executeSymbol = execute ? lowercaseSpecial : Character(String(lowercaseSpecial).uppercased())
            } else {
                executeSymbol = execute ? "x" : "-"
            }

            return "\(read ? "r" : "-")\(write ? "w" : "-")\(executeSymbol)"
        }
    }

    public var setuid: Bool
    public var setgid: Bool
    public var sticky: Bool
    public var owner: PermissionTriad
    public var group: PermissionTriad
    public var other: PermissionTriad

    public init(
        setuid: Bool = false,
        setgid: Bool = false,
        sticky: Bool = false,
        owner: PermissionTriad,
        group: PermissionTriad,
        other: PermissionTriad
    ) {
        self.setuid = setuid
        self.setgid = setgid
        self.sticky = sticky
        self.owner = owner
        self.group = group
        self.other = other
    }

    public init(octal raw: String) throws(ParseError) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(trimmed.utf8)
        guard bytes.count == 3 || bytes.count == 4 else {
            throw .invalidLength
        }
        guard bytes.allSatisfy({ (48...57).contains($0) }) else {
            throw .nonOctalDigit
        }
        guard bytes.allSatisfy({ $0 <= 55 }) else {
            throw .digitOutOfRange
        }

        let values = bytes.map { Int($0 - 48) }
        let special = values.count == 4 ? values[0] : 0
        let permissionOffset = values.count - 3

        setuid = special & 4 != 0
        setgid = special & 2 != 0
        sticky = special & 1 != 0
        owner = PermissionTriad(octalValue: values[permissionOffset])
        group = PermissionTriad(octalValue: values[permissionOffset + 1])
        other = PermissionTriad(octalValue: values[permissionOffset + 2])
    }

    public static let standard644 = ChmodMode(
        owner: PermissionTriad(read: true, write: true, execute: false),
        group: PermissionTriad(read: true, write: false, execute: false),
        other: PermissionTriad(read: true, write: false, execute: false)
    )

    public var octalString: String {
        let permissions = "\(owner.octalValue)\(group.octalValue)\(other.octalValue)"
        let special = (setuid ? 4 : 0) + (setgid ? 2 : 0) + (sticky ? 1 : 0)
        return special == 0 ? permissions : "\(special)\(permissions)"
    }

    public var symbolicString: String {
        owner.symbolic(special: setuid, lowercaseSpecial: "s")
            + group.symbolic(special: setgid, lowercaseSpecial: "s")
            + other.symbolic(special: sticky, lowercaseSpecial: "t")
    }
}
