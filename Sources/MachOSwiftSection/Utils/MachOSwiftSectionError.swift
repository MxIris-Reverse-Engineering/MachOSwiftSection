import Foundation
import MachOKit
import MachOFoundation

enum MachOSwiftSectionError: LocalizedError {
    case sectionNotFound(section: MachOSwiftSectionName, allSectionNames: [String])
    case invalidSectionAlignment(section: MachOSwiftSectionName, align: Int)

    var errorDescription: String? {
        switch self {
        case let .sectionNotFound(section, allSectionNames):
            return "Swift section \(section.rawValue) not found in Mach-O. Available sections: \(allSectionNames.joined(separator: ", "))"
        case let .invalidSectionAlignment(section, align):
            return "Invalid alignment for Swift section \(section.rawValue). Expected alignment is 4, but found \(align)."
        }
    }
}
