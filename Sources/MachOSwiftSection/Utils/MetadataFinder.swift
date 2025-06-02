import Foundation
import MachOKit
import MachOFoundation

protocol MachODataSectionProvider {
    var dataConst: (any SectionProtocol)? { get }
    var data: (any SectionProtocol)? { get }
}

protocol MachOOffsetConverter {
    func offset(of address: UInt64) -> Int
}

extension MachOFile: MachOOffsetConverter {
    func offset(of address: UInt64) -> Int {
        if let cache, let offset = cache.fileOffset(of: address) {
            return offset.cast()
        } else {
            return fileOffset(of: address).cast()
        }
    }
}

extension MachOImage: MachOOffsetConverter {
    func offset(of address: UInt64) -> Int {
        numericCast(address - ptr.uint.cast())
    }
}

extension MachOFile: MachODataSectionProvider {
    var dataConst: (any SectionProtocol)? {
        return loadCommands.dataConst64?._section(for: "__const", in: self)
    }

    var data: (any SectionProtocol)? {
        return loadCommands.data64?._section(for: "__data", in: self)
    }
}

extension MachOImage: MachODataSectionProvider {
    var dataConst: (any SectionProtocol)? {
        return loadCommands.dataConst64?._section(for: "__const", in: self)
    }

    var data: (any SectionProtocol)? {
        return loadCommands.data64?._section(for: "__data", in: self)
    }
}

protocol TypeMetadataProtocol: MetadataProtocol {
    static var descriptorOffset: Int { get }
}

class MetadataFinder<MachO: MachORepresentable & MachOReadable & MachODataSectionProvider & MachOOffsetConverter> {
    let machO: MachO

    private var metadataOffsetByDescriptorOffset: [Int: Int] = [:]

    init(machO: MachO) {
        self.machO = machO

        buildOffsetMap()
    }

    private func buildOffsetMap() {
        if let section = machO.dataConst {
            var currentOffset = section.offset
            let endOffset = section.offset + section.size
            while currentOffset < endOffset {
                do {
                    let address = try machO.readElement(offset: currentOffset) as UInt64
                    metadataOffsetByDescriptorOffset[machO.offset(of: address)] = currentOffset
                } catch {
                    print(error)
                }
                currentOffset.offset(of: UInt64.self)
            }
        }

        if let section = machO.data {
            var currentOffset = section.offset
            let endOffset = section.offset + section.size
            while currentOffset < endOffset {
                do {
                    let address = try machO.readElement(offset: currentOffset) as UInt64
                    metadataOffsetByDescriptorOffset[machO.offset(of: address)] = currentOffset
                } catch {
                    print(error)
                }

                currentOffset.offset(of: UInt64.self)
            }
        }
    }

    public func metadata<Descriptor: TypeContextDescriptorProtocol, Metadata: TypeMetadataProtocol>(for descriptor: Descriptor) throws -> Metadata? {
        guard let offset = metadataOffsetByDescriptorOffset[descriptor.offset] else { return nil }
        return try machO.readWrapperElement(offset: offset - Metadata.descriptorOffset) as Metadata
    }
}
