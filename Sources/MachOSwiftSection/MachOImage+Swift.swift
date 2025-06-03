import Foundation
import MachOKit
import MachOFoundation

extension MachOImage {
    public struct Swift {
        private let machOImage: MachOImage

        fileprivate init(machOImage: MachOImage) {
            self.machOImage = machOImage
        }
    }

    public var swift: Swift {
        .init(machOImage: self)
    }
}

extension MachOImage.Swift {
    public var protocolDescriptors: [ProtocolDescriptor] {
        get throws {
            return try _readDescriptors(from: .__swift5_protos, in: machOImage)
        }
    }

    public var protocolConformanceDescriptors: [ProtocolConformanceDescriptor] {
        get throws {
            return try _readDescriptors(from: .__swift5_proto, in: machOImage)
        }
    }

    public var typeContextDescriptors: [ContextDescriptorWrapper] {
        get throws {
            return try _readDescriptors(from: .__swift5_types, in: machOImage) + _readDescriptors(from: .__swift5_types2, in: machOImage)
        }
    }
}

extension MachOImage.Swift {
    private func _section(for swiftMachOSection: MachOSwiftSectionName, in machOImage: MachOImage) throws -> (any SectionProtocol) {
        let loadCommands = machOImage.loadCommands
        let swiftSection: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text._section(for: swiftMachOSection, in: machOImage) {
            swiftSection = section
        } else if let text = loadCommands.text,
                  let section = text._section(for: swiftMachOSection, in: machOImage) {
            swiftSection = section
        } else {
            throw MachOSwiftSectionError.sectionNotFound(section: swiftMachOSection, allSectionNames: machOImage.sections.map(\.sectionName))
        }
        guard swiftSection.align * 2 == 4 else {
            
                throw MachOSwiftSectionError.invalidSectionAlignment(section: swiftMachOSection, align: swiftSection.align)
        }
        return swiftSection
    }

    private func _readDescriptors<Descriptor: Resolvable>(from swiftMachOSection: MachOSwiftSectionName, in machOImage: MachOImage) throws -> [Descriptor] {
        let section = try _section(for: swiftMachOSection, in: machOImage)
        return try _readDescriptors(from: section, in: machOImage)
    }

    private func _readDescriptors<Descriptor: Resolvable>(from section: any SectionProtocol, in machO: MachOImage) throws -> [Descriptor] {
        let vmaddrSlide = try required(machO.vmaddrSlide)
        let start = try required(UnsafeRawPointer(bitPattern: section.address + vmaddrSlide))
        
        let offset = start.int - machO.ptr.int
        
        let pointerSize: Int = MemoryLayout<RelativeDirectPointer<Descriptor>>.size

        let data: [AnyLocatableLayoutWrapper<RelativeDirectPointer<Descriptor>>] = try machO.readElements(offset: offset, numberOfElements: section.size / pointerSize)

        return try data.map { try $0.layout.resolve(from: $0.offset, in: machO) }
    }
}
