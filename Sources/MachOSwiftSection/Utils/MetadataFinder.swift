import Foundation
import MachOKit
import MachOFoundation

protocol MachODataSectionProvider {
    var dataSections: [any SectionProtocol] { get }
}

protocol MachOOffsetConverter {
    func offset(of address: UInt64, at fileOffset: Int) -> Int
}

extension MachOFile: MachOOffsetConverter {
    func offset(of address: UInt64, at fileOffset: Int) -> Int {
        if cache != nil, let offset = resolveRebase(fileOffset: fileOffset) {
            return offset.cast()
        } else {
            return self.fileOffset(of: address).cast()
        }
    }
}

extension MachOImage: MachOOffsetConverter {
    func offset(of address: UInt64, at fileOffset: Int) -> Int {
        numericCast(address - ptr.uint.cast())
    }
}

extension MachOFile: MachODataSectionProvider {
    var dataSections: [any SectionProtocol] {
        [
            loadCommands.dataConst64?._section(for: "__const", in: self),
            loadCommands.data64?._section(for: "__data", in: self),
            loadCommands.auth64?._section(for: "__data", in: self),
        ].compactMap { $0 }
    }
}

extension MachOImage: MachODataSectionProvider {
    var dataSections: [any SectionProtocol] {
        [
            loadCommands.dataConst64?._section(for: "__const", in: self),
            loadCommands.data64?._section(for: "__data", in: self),
            loadCommands.auth64?._section(for: "__data", in: self),
        ].compactMap { $0 }
    }
}

protocol TypeMetadataProtocol: MetadataProtocol {
    static var descriptorOffset: Int { get }
}

class MetadataFinder<MachO: MachORepresentableWithCache & MachOReadable & MachODataSectionProvider & MachOOffsetConverter> {
    let machO: MachO

    private var metadataOffsetByDescriptorOffset: [Int: Int] = [:]

    init(machO: MachO) {
        self.machO = machO

        buildOffsetMap()
    }

    private func buildOffsetMap() {
        func build(section: any SectionProtocol) {
            var currentOffset = if let cache = machO.cache {
                section.address - cache.mainCacheHeader.sharedRegionStart.cast()
            } else {
                section.offset
            }
            let endOffset = currentOffset + section.size
            while currentOffset < endOffset {
                do {
                    let address = try machO.readElement(offset: currentOffset) as UInt64
                    print(currentOffset, address)
                    metadataOffsetByDescriptorOffset[machO.offset(of: address, at: currentOffset)] = currentOffset
                } catch {
                    print(error)
                }
                currentOffset.offset(of: UInt64.self)
            }
        }

        for dataSection in machO.dataSections {
            build(section: dataSection)
        }
    }

    public func metadata<Descriptor: TypeContextDescriptorProtocol, Metadata: TypeMetadataProtocol>(for descriptor: Descriptor) throws -> Metadata? {
        guard let offset = metadataOffsetByDescriptorOffset[descriptor.offset] else { return nil }
        return try machO.readWrapperElement(offset: offset - Metadata.descriptorOffset) as Metadata
    }
}
