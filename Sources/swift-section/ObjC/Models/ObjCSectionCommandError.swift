import Foundation

/// The failures only the `objc` subcommands can hit. Loading the binary is
/// shared with the Swift commands, so its failures are
/// ``SwiftSectionCommandError`` cases — with the same wording `objc-section`
/// printed before it moved here.
enum ObjCSectionCommandError: LocalizedError {
    case malformedCTypeReplacement(String)
    case unknownCType(String)
    case declarationNotFound(String)

    var errorDescription: String? {
        switch self {
        case .malformedCTypeReplacement(let argument):
            "Malformed --c-type-replacement '\(argument)'. Expected <c-type>=<replacement>, e.g. double=CGFloat."
        case .unknownCType(let name):
            "Unknown C type '\(name)'. Supported: \(CTypeName.allSpellings.joined(separator: ", "))."
        case .declarationNotFound(let name):
            "No class, protocol, category, struct or union named '\(name)' in this binary."
        }
    }
}
