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
        let loadCommands = machOFile.loadCommands

        let __swift5_protos: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text.__swift5_protos(in: machOFile) {
            __swift5_protos = section
        } else if let text = loadCommands.text,
                  let section = text.__swift5_protos(in: machOFile) {
            __swift5_protos = section
        } else {
            return nil
        }
        guard __swift5_protos.align * 2 == 4 else {
            return nil
        }
        return try? _readDescriptors(from: __swift5_protos, in: machOFile)
    }

    public var protocolConformanceDescriptors: [ProtocolConformanceDescriptor]? {
        let loadCommands = machOFile.loadCommands

        let __swift5_proto: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text.__swift5_proto(in: machOFile) {
            __swift5_proto = section
        } else if let text = loadCommands.text,
                  let section = text.__swift5_proto(in: machOFile) {
            __swift5_proto = section
        } else {
            return nil
        }
        guard __swift5_proto.align * 2 == 4 else {
            return nil
        }
        return try? _readDescriptors(from: __swift5_proto, in: machOFile)
    }

    public var typeContextDescriptors: [TypeContextDescriptor]? {
        let loadCommands = machOFile.loadCommands

        let __swift5_types: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text.__swift5_types(in: machOFile) {
            __swift5_types = section
        } else if let text = loadCommands.text,
                  let section = text.__swift5_types(in: machOFile) {
            __swift5_types = section
        } else {
            return nil
        }
        guard __swift5_types.align * 2 == 4 else {
            return nil
        }
        return try? _readDescriptors(from: __swift5_types, in: machOFile)
    }
}

extension MachOFile.Swift {
    private func _readDescriptors<Descriptor: LocatableLayoutWrapper>(from section: any SectionProtocol, in machO: MachOFile) throws -> [Descriptor] {
        let pointerSize: Int = MemoryLayout<RelativeDirectPointer<Descriptor>>.size

        let data: [AnyLocatableLayoutWrapper<RelativeDirectPointer<Descriptor>>] = try machO.readElements(offset: section.offset.cast(), numberOfElements: section.size / pointerSize)

        return try data.map { try $0.layout.resolve(from: $0.offset, in: machO) }
    }
}
