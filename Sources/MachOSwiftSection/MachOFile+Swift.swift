import Foundation
@_spi(Support) import MachOKit

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
        return _readProtocolDescriptors(from: __swift5_protos, in: machO)
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
        return _readTypeContextDescriptors(from: __swift5_types, in: machO)
    }
}

enum TypeContextDescriptorWrapper {
    case `enum`(EnumDescriptor)
}

public enum ContextDescriptorWrapper {
    case `type`(TypeContextDescriptor)
    case `protocol`(ProtocolDescriptor)
}

extension MachOFile.Swift {
    func _readContextDescriptor(from offset: UInt64, in machOFile: MachOFile) -> ContextDescriptorWrapper? {
        let contextDescriptorLayout: ContextDescriptor.Layout = machOFile.fileHandle.read(offset: offset + numericCast(machOFile.headerStartOffset))
        let contextDescriptor = ContextDescriptor(offset: numericCast(offset), layout: contextDescriptorLayout)
        switch contextDescriptor.flags.kind {
        case .class,
             .enum,
             .struct,
             .module:
            let contextDescriptorLayout: TypeContextDescriptor.Layout = machOFile.fileHandle.read(offset: offset + numericCast(machOFile.headerStartOffset))
            return .type(TypeContextDescriptor(offset: numericCast(offset), layout: contextDescriptorLayout))
        case .protocol:
            let contextDescriptorLayout: ProtocolDescriptor.Layout = machOFile.fileHandle.read(offset: offset + numericCast(machOFile.headerStartOffset))
            return .protocol(ProtocolDescriptor(offset: numericCast(offset), layout: contextDescriptorLayout))
        default:
            return nil
        }
    }

    func _readTypeContextDescriptors(from section: any SectionProtocol, in machO: MachOFile) -> [TypeContextDescriptor]? {
        let data = machO.fileHandle.readData(
            offset: numericCast(section.offset + machO.headerStartOffset),
            size: section.size
        )

        let pointerSize: Int = MemoryLayout<RelativeOffset>.size
        let offsets: DataSequence<RelativeOffset> = .init(
            data: data,
            numberOfElements: section.size / pointerSize
        )

        return offsets
            .enumerated()
            .map { (offsetIndex: Int, nominalLocalOffset: RelativeOffset) in
                let offset = Int(nominalLocalOffset) + (offsetIndex * 4) + section.offset
                let layout: TypeContextDescriptor.Layout = machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
                return .init(offset: numericCast(offset), layout: layout)
            }
    }

    func _readProtocolDescriptors(from section: any SectionProtocol, in machO: MachOFile) -> [ProtocolDescriptor]? {
        let data = machO.fileHandle.readData(
            offset: numericCast(section.offset + machO.headerStartOffset),
            size: section.size
        )

        let pointerSize: Int = MemoryLayout<RelativeOffset>.size
        let offsets: DataSequence<RelativeOffset> = .init(
            data: data,
            numberOfElements: section.size / pointerSize
        )

        return offsets
            .enumerated()
            .map { (offsetIndex: Int, rawOffset: RelativeOffset) in
                let offset = Int(rawOffset) + (offsetIndex * 4) + section.offset
                let layout: ProtocolDescriptor.Layout = machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
                return .init(offset: numericCast(offset), layout: layout)
            }
    }
}
