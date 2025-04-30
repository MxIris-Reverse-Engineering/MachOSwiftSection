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
    public var protocols: [SwiftProtocolDescriptor]? {
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
        return _readProtocols(from: __swift5_protos, in: machO)
    }

    public var nominalTypes: [SwiftNominalTypeDescriptor]? {
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
        return _readNominalTypes(from: __swift5_types, in: machO)
    }
}

extension MachOFile.Swift {
    func _readTypeContextDescriptor(from offset: UInt64, in machOFile: MachOFile) -> SwiftTypeContextDescriptor? {
        let contextDescriptorLayout: SwiftContextDescriptor.Layout = machOFile.fileHandle.read(offset: offset + numericCast(machOFile.headerStartOffset))
        let contextDescriptor = SwiftContextDescriptor(offset: numericCast(offset), layout: contextDescriptorLayout)
        switch contextDescriptor.flags.kind {
        case .class,
             .enum,
             .protocol,
             .struct:
            let contextDescriptorLayout: SwiftTypeContextDescriptor.Layout = machOFile.fileHandle.read(offset: offset + numericCast(machOFile.headerStartOffset))
            let typeContextDescriptor = SwiftTypeContextDescriptor(offset: numericCast(offset), layout: contextDescriptorLayout)
            return typeContextDescriptor
        default:
            return nil
        }
    }

    func _readNominalTypes(from section: any SectionProtocol, in machO: MachOFile) -> [SwiftNominalTypeDescriptor]? {
        let data = machO.fileHandle.readData(
            offset: numericCast(section.offset + machO.headerStartOffset),
            size: section.size
        )

        let pointerSize: Int = MemoryLayout<RelativeDirectPointer>.size
        let offsets: DataSequence<RelativeDirectPointer> = .init(
            data: data,
            numberOfElements: section.size / pointerSize
        )

        return offsets
            .enumerated()
            .map { (offsetIndex: Int, nominalLocalOffset: RelativeDirectPointer) in
                let offset = Int(nominalLocalOffset) + (offsetIndex * 4) + section.offset
                let layout: SwiftNominalTypeDescriptor.Layout = machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
                return .init(offset: numericCast(offset), layout: layout)
            }
    }

    func _readProtocols(from section: any SectionProtocol, in machO: MachOFile) -> [SwiftProtocolDescriptor]? {
        let data = machO.fileHandle.readData(
            offset: numericCast(section.offset + machO.headerStartOffset),
            size: section.size
        )

        let pointerSize: Int = MemoryLayout<RelativeDirectPointer>.size
        let offsets: DataSequence<RelativeDirectPointer> = .init(
            data: data,
            numberOfElements: section.size / pointerSize
        )

        return offsets
            .enumerated()
            .map { (offsetIndex: Int, rawOffset: RelativeDirectPointer) in
                let offset = Int(rawOffset) + (offsetIndex * 4) + section.offset
                let layout: SwiftProtocolDescriptor.Layout = machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
                return .init(layout: layout, offset: numericCast(offset))
            }
    }
}
