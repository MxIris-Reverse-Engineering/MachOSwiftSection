import Foundation
import MachOKit


extension MachOFile {
    func section(for swiftMachOSection: MachOSwiftSectionName) throws -> (any SectionProtocol) {
        let loadCommands = loadCommands
        let swiftSection: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text._section(for: swiftMachOSection.rawValue, in: self) {
            swiftSection = section
        } else if let text = loadCommands.text,
                  let section = text._section(for: swiftMachOSection.rawValue, in: self) {
            swiftSection = section
        } else if let section = sections.first(where: { $0.sectionName == swiftMachOSection.rawValue }) {
            swiftSection = section
        } else {
            throw MachOSwiftSectionError.sectionNotFound(section: swiftMachOSection, allSectionNames: sections.map(\.sectionName))
        }
        guard swiftSection.align * 2 == 4 else {
            throw MachOSwiftSectionError.invalidSectionAlignment(section: swiftMachOSection, align: swiftSection.align)
        }
        return swiftSection
    }
}

extension MachOImage {
    func section(for swiftMachOSection: MachOSwiftSectionName) throws -> (any SectionProtocol) {
        let loadCommands = loadCommands
        let swiftSection: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text._section(for: swiftMachOSection.rawValue, in: self) {
            swiftSection = section
        } else if let text = loadCommands.text,
                  let section = text._section(for: swiftMachOSection.rawValue, in: self) {
            swiftSection = section
        } else if let section = sections.first(where: { $0.sectionName == swiftMachOSection.rawValue }) {
            swiftSection = section
        } else {
            throw MachOSwiftSectionError.sectionNotFound(section: swiftMachOSection, allSectionNames: sections.map(\.sectionName))
        }
        guard swiftSection.align * 2 == 4 else {
            throw MachOSwiftSectionError.invalidSectionAlignment(section: swiftMachOSection, align: swiftSection.align)
        }
        return swiftSection
    }
}
