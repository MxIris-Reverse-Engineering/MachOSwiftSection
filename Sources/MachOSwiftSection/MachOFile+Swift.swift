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
    
    func _readNominalTypes<NominalType: SwiftNominalTypeDescriptorProtocol>(from section: any SectionProtocol, in machO: MachOFile) -> [NominalType]? {
        let data = machO.fileHandle.readData(
            offset: numericCast(section.offset + machO.headerStartOffset),
            size: section.size
        )

        typealias Pointer = NominalType.Layout.Pointer
        let pointerSize: Int = MemoryLayout<Pointer>.size
        let offsets: DataSequence<Pointer> = .init(
            data: data,
            numberOfElements: section.size / pointerSize
        )

        return offsets
            .enumerated()
            .map { (offsetIndex: Int, nominalLocalOffset: Pointer) in
                let offset = Int(nominalLocalOffset) + (offsetIndex * 4) + section.offset
                let layout: NominalType.Layout = machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
                return .init(offset: numericCast(offset), layout: layout)
            }
    }
    
    
    func _readProtocols<Protocol: SwiftProtocolDescriptorProtocol>(from section: any SectionProtocol, in machO: MachOFile) -> [Protocol]? {
        let data = machO.fileHandle.readData(
            offset: numericCast(section.offset + machO.headerStartOffset),
            size: section.size
        )

        typealias Pointer = Protocol.Layout.Pointer
        let pointerSize: Int = MemoryLayout<Pointer>.size
        let offsets: DataSequence<Pointer> = .init(
            data: data,
            numberOfElements: section.size / pointerSize
        )

        return offsets
            .enumerated()
            .map { (offsetIndex: Int, rawOffset: Pointer) in
                let offset = Int(rawOffset) + (offsetIndex * 4) + section.offset
                let layout: Protocol.Layout = machO.fileHandle.read(offset: numericCast(offset + machO.headerStartOffset))
                return .init(layout: layout, offset: numericCast(offset))
            }
    }
    
    
}

