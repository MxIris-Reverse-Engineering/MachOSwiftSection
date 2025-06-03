import Foundation
import MachOKit
import MachOFoundation

extension MachOFile {
    public struct Swift {
        private let machOFile: MachOFile

        fileprivate init(machOFile: MachOFile) {
            self.machOFile = machOFile
        }
    }

    public var swift: Swift {
        .init(machOFile: self)
    }
}

enum MachOSwiftSectionError: LocalizedError {
    case sectionNotFound(section: MachOSwiftSectionName, allSectionNames: [String])
    case invalidSectionAlignment(section: MachOSwiftSectionName, align: Int)
    
    var errorDescription: String? {
        switch self {
        case .sectionNotFound(let section, let allSectionNames):
            return "Swift section \(section.rawValue) not found in Mach-O. Available sections: \(allSectionNames.joined(separator: ", "))"
        case .invalidSectionAlignment(let section, let align):
            return "Invalid alignment for Swift section \(section.rawValue). Expected alignment is 4, but found \(align)."
        }
    }
}

extension MachOFile.Swift {
    public var protocolDescriptors: [ProtocolDescriptor] {
        get throws {
            return try _readDescriptors(from: .__swift5_protos, in: machOFile)
        }
    }

    public var protocolConformanceDescriptors: [ProtocolConformanceDescriptor] {
        get throws {
            return try _readDescriptors(from: .__swift5_proto, in: machOFile)
        }
    }

    public var typeContextDescriptors: [ContextDescriptorWrapper] {
        get throws {
            return try _readDescriptors(from: .__swift5_types, in: machOFile) + (try? _readDescriptors(from: .__swift5_types2, in: machOFile))
        }
    }

    public var associatedTypeDescriptors: [AssociatedTypeDescriptor] {
        get throws {
            let section = try _section(for: .__swift5_assocty, in: machOFile)
            var associatedTypeDescriptors: [AssociatedTypeDescriptor] = []
            let offset = if let cache = machOFile.cache {
                section.address - cache.mainCacheHeader.sharedRegionStart.cast()
            } else {
                section.offset
            }
            var currentOffset = offset
            let endOffset = offset + section.size
            while currentOffset < endOffset {
                let associatedTypeDescriptor: AssociatedTypeDescriptor = try machOFile.readElement(offset: currentOffset)
                currentOffset += associatedTypeDescriptor.size
                associatedTypeDescriptors.append(associatedTypeDescriptor)
            }
            return associatedTypeDescriptors
        }
    }
}

extension MachOFile.Swift {
    private func _section(for swiftMachOSection: MachOSwiftSectionName, in machOFile: MachOFile) throws -> (any SectionProtocol) {
        let loadCommands = machOFile.loadCommands
        let swiftSection: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text._section(for: swiftMachOSection, in: machOFile) {
            swiftSection = section
        } else if let text = loadCommands.text,
                  let section = text._section(for: swiftMachOSection, in: machOFile) {
            swiftSection = section
        } else {
            throw MachOSwiftSectionError.sectionNotFound(section: swiftMachOSection, allSectionNames: machOFile.sections.map(\.sectionName))
        }
        guard swiftSection.align * 2 == 4 else {
            throw MachOSwiftSectionError.invalidSectionAlignment(section: swiftMachOSection, align: swiftSection.align)
        }
        return swiftSection
    }

    private func _readDescriptors<Descriptor: Resolvable>(from swiftMachOSection: MachOSwiftSectionName, in machOFile: MachOFile) throws -> [Descriptor] {
        let section = try _section(for: swiftMachOSection, in: machOFile)
        return try _readDescriptors(from: section, in: machOFile)
    }

    private func _readDescriptors<Descriptor: Resolvable>(from section: any SectionProtocol, in machO: MachOFile) throws -> [Descriptor] {
        let pointerSize: Int = MemoryLayout<RelativeDirectPointer<Descriptor>>.size
        let offset = if let cache = machO.cache {
            section.address - cache.mainCacheHeader.sharedRegionStart.cast()
        } else {
            section.offset
        }
        let data: [AnyLocatableLayoutWrapper<RelativeDirectPointer<Descriptor>>] = try machO.readElements(offset: offset, numberOfElements: section.size / pointerSize)

        return try data.map { try $0.layout.resolve(from: $0.offset, in: machO) }
    }
}

func + <Element>(lhs: [Element]?, rhs: [Element]?) -> [Element] {
    (lhs ?? []) + (rhs ?? [])
}

func + <Element>(lhs: [Element], rhs: [Element]?) -> [Element] {
    lhs + (rhs ?? [])
}

func + <Element>(lhs: [Element]?, rhs: [Element]) -> [Element] {
    (lhs ?? []) + rhs
}
