import Foundation

/// The command-line spellings only the `objc` subcommands parse. Loading the
/// binary is shared with the Swift commands, so its failures are
/// ``SwiftSectionCommandError`` cases; a declaration that is not found is the
/// library's `ObjCDeclarationLookupError`.
enum ObjCSectionCommandError: LocalizedError {
    case malformedCTypeReplacement(String)
    case unknownCType(String)

    var errorDescription: String? {
        switch self {
        case .malformedCTypeReplacement(let argument):
            "Malformed --c-type-replacement '\(argument)'. Expected <c-type>=<replacement>, e.g. double=CGFloat."
        case .unknownCType(let name):
            "Unknown C type '\(name)'. Supported: \(CTypeName.allSpellings.joined(separator: ", "))."
        }
    }
}
