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
    public var protocols: [SwiftProtocol]? {
//        guard machO.is64Bit else { return nil }
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
        return _readProtocols(from: __swift5_protos, in: machO)
    }
}

extension MachOFile.Swift {
    func _readProtocols<Protocol: SwiftProtocolProtocol>(from section: any SectionProtocol, in machO: MachOFile) -> [Protocol]? {
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
                let offset = Int(rawOffset) + (offsetIndex * 4) + section.offset + machO.headerStartOffset
                let layout: Protocol.Layout = machO.fileHandle.read(offset: machO.fileOffset(of: numericCast(offset)))
                return .init(layout: layout, offset: numericCast(offset))
            }
    }
}

