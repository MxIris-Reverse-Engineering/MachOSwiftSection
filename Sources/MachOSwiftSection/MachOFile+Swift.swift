import Foundation
import MachOKit

extension MachOFile {
    public struct Swift {
        private let machO: MachOFile

        init(machO: MachOFile) {
            self.machO = machO
        }
    }

    public var swift: Swift {
        .init(machO: self)
    }
}

extension MachOFile.Swift {
    public var protocolDescriptors: [ProtocolDescriptor]? {
        let loadCommands = machO.loadCommands

        let __swift5_protos: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text.__swift5_protos(in: machO) {
            __swift5_protos = section
        } else if let text = loadCommands.text,
                  let section = text.__swift5_protos(in: machO) {
            __swift5_protos = section
        } else {
            return nil
        }
        guard __swift5_protos.align * 2 == 4 else {
            return nil
        }
        return try? _readProtocolDescriptors(from: __swift5_protos, in: machO)
    }

    public var typeContextDescriptors: [TypeContextDescriptor]? {
        let loadCommands = machO.loadCommands

        let __swift5_types: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text.__swift5_types(in: machO) {
            __swift5_types = section
        } else if let text = loadCommands.text,
                  let section = text.__swift5_types(in: machO) {
            __swift5_types = section
        } else {
            return nil
        }
        guard __swift5_types.align * 2 == 4 else {
            return nil
        }
        return try? _readTypeContextDescriptors(from: __swift5_types, in: machO)
    }
}

extension MachOFile.Swift {
    func _readContextDescriptor(from offset: Int) throws -> ContextDescriptorWrapper? {
        let contextDescriptor: ContextDescriptor = try machO.readElement(offset: offset)
        switch contextDescriptor.flags.kind {
        case .class:
            return try .type(.class(machO.readElement(offset: offset)))
        case .enum:
            return try .type(.enum(machO.readElement(offset: offset)))
        case .struct:
            return try .type(.struct(machO.readElement(offset: offset)))
        case .protocol:
            return try .protocol(machO.readElement(offset: offset))
        case .anonymous:
            return try .anonymous(machO.readElement(offset: offset))
        case .extension:
            return try .extension(machO.readElement(offset: offset))
        case .module:
            return try .module(machO.readElement(offset: offset))
        case .opaqueType:
            return try .opaqueType(machO.readElement(offset: offset))
        default:
            return nil
        }
    }

    func _readTypeContextDescriptors(from section: any SectionProtocol, in machO: MachOFile) throws -> [TypeContextDescriptor] {
        return try _readDescriptors(from: section, in: machO)
    }

    func _readProtocolDescriptors(from section: any SectionProtocol, in machO: MachOFile) throws -> [ProtocolDescriptor] {
        return try _readDescriptors(from: section, in: machO)
    }

    func _readDescriptors<Descriptor: LocatableLayoutWrapper>(from section: any SectionProtocol, in machO: MachOFile) throws -> [Descriptor] {
        let pointerSize: Int = MemoryLayout<RelativeDirectPointer<Descriptor>>.size

        let data: [AnyLocatableLayoutWrapper<RelativeDirectPointer<Descriptor>>] = try machO.readElements(offset: section.offset.cast(), numberOfElements: section.size / pointerSize)

        return try data.map { try $0.layout.resolve(from: $0.offset, in: machO) }
    }
}
