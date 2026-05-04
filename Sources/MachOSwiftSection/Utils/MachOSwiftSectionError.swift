import Foundation
import MachOKit
import MachOFoundation

public enum MachOSwiftSectionError: LocalizedError, Sendable {
    case sectionNotFound(section: MachOSwiftSectionName, allSectionNames: [String])
    case invalidSectionAlignment(section: MachOSwiftSectionName, align: Int)
    case unknownMetadataKind(rawValue: UInt)

    public var errorDescription: String? {
        switch self {
        case .sectionNotFound(let section, let allSectionNames):
            return "Swift section \(section.rawValue) not found in Mach-O. Available sections: \(allSectionNames.joined(separator: ", "))"
        case .invalidSectionAlignment(let section, let align):
            return "Invalid alignment for Swift section \(section.rawValue). Expected alignment is 4, but found \(align)."
        case .unknownMetadataKind(let rawValue):
            return "Unknown metadata kind: 0x\(String(rawValue, radix: 16)). MetadataWrapper cannot resolve metadata of an unrecognized kind."
        }
    }
}
