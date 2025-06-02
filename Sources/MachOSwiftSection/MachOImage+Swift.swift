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
    public var protocolDescriptors: [ProtocolDescriptor]? {
        return _readDescriptors(from: .__swift5_protos, in: machOImage)
    }

    public var protocolConformanceDescriptors: [ProtocolConformanceDescriptor]? {
        return _readDescriptors(from: .__swift5_proto, in: machOImage)
    }

    public var typeContextDescriptors: [ContextDescriptorWrapper]? {
        return _readDescriptors(from: .__swift5_types, in: machOImage) + _readDescriptors(from: .__swift5_types2, in: machOImage)
    }
}

extension MachOImage.Swift {
    private func _section(for swiftMachOSection: MachOSwiftSectionName, in machOImage: MachOImage) -> (any SectionProtocol)? {
        let loadCommands = machOImage.loadCommands
        let swiftSection: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text._section(for: swiftMachOSection, in: machOImage) {
            swiftSection = section
        } else if let text = loadCommands.text,
                  let section = text._section(for: swiftMachOSection, in: machOImage) {
            swiftSection = section
        } else {
            return nil
        }
        guard swiftSection.align * 2 == 4 else {
            return nil
        }
        return swiftSection
    }

    private func _readDescriptors<Descriptor: Resolvable>(from swiftMachOSection: MachOSwiftSectionName, in machOImage: MachOImage) -> [Descriptor]? {
        guard let section = _section(for: swiftMachOSection, in: machOImage) else { return nil }
        return try? _readDescriptors(from: section, in: machOImage)
    }

    private func _readDescriptors<Descriptor: Resolvable>(from section: any SectionProtocol, in machO: MachOImage) throws -> [Descriptor]? {
        guard let vmaddrSlide = machO.vmaddrSlide else { return nil }
        guard let start = UnsafeRawPointer(
            bitPattern: section.address + vmaddrSlide
        ) else { return nil }
        
        let offset = start.int - machO.ptr.int
        
        let pointerSize: Int = MemoryLayout<RelativeDirectPointer<Descriptor>>.size

        let data: [AnyLocatableLayoutWrapper<RelativeDirectPointer<Descriptor>>] = try machO.readElements(offset: offset, numberOfElements: section.size / pointerSize)

        return try data.map { try $0.layout.resolve(from: $0.offset, in: machO) }
    }
}
