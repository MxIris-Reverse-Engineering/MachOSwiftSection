import Foundation
import MachOKit

extension MachOFile {
    public struct Swift {
        private let machOFile: MachOFile

        init(machOFile: MachOFile) {
            self.machOFile = machOFile
        }
    }

    public var swift: Swift {
        .init(machOFile: self)
    }
}

extension MachOFile.Swift {
    public var protocolDescriptors: [ProtocolDescriptor]? {
        return _readDescriptors(from: .__swift5_protos, in: machOFile)
    }

    public var protocolConformanceDescriptors: [ProtocolConformanceDescriptor]? {
        return _readDescriptors(from: .__swift5_proto, in: machOFile)
    }

    public var typeContextDescriptors: [TypeContextDescriptor]? {
        return _readDescriptors(from: .__swift5_types, in: machOFile)
    }
}

extension MachOFile.Swift {
    private func _readDescriptors<Descriptor: LocatableLayoutWrapper>(from swiftMachOSection: SwiftMachOSection, in machOFile: MachOFile) -> [Descriptor]? {
        let loadCommands = machOFile.loadCommands
        let swiftSection: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text._section(for: swiftMachOSection, in: machOFile) {
            swiftSection = section
        } else if let text = loadCommands.text,
                  let section = text._section(for: swiftMachOSection, in: machOFile) {
            swiftSection = section
        } else {
            return nil
        }
        guard swiftSection.align * 2 == 4 else {
            return nil
        }
        return try? _readDescriptors(from: swiftSection, in: machOFile)
    }

    private func _readDescriptors<Descriptor: LocatableLayoutWrapper>(from section: any SectionProtocol, in machO: MachOFile) throws -> [Descriptor] {
        let pointerSize: Int = MemoryLayout<RelativeDirectPointer<Descriptor>>.size

        let data: [AnyLocatableLayoutWrapper<RelativeDirectPointer<Descriptor>>] = try machO.readElements(offset: section.offset.cast(), numberOfElements: section.size / pointerSize)

        return try data.map { try $0.layout.resolve(from: $0.offset, in: machO) }
    }
}
