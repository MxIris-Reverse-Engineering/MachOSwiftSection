import Foundation
import MachOKit
import MachOFoundation

package protocol MachOOffsetConverter {
    func offset(of address: UInt64, at fileOffset: Int) -> Int
}

extension MachOFile: MachOOffsetConverter {
    package func offset(of address: UInt64, at fileOffset: Int) -> Int {
        if cache != nil, let offset = resolveRebase(fileOffset: fileOffset) {
            return offset.cast()
        } else {
            return self.fileOffset(of: address).cast()
        }
    }
}

extension MachOImage: MachOOffsetConverter {
    package func offset(of address: UInt64, at fileOffset: Int) -> Int {
        numericCast(address - ptr.uint.cast())
    }
}

extension MachORepresentableWithCache {
    package var dataSections: [any SectionProtocol] {
        [
            loadCommands.dataConst64?._section(for: "__const", in: self),
            loadCommands.data64?._section(for: "__data", in: self),
            loadCommands.auth64?._section(for: "__data", in: self),
        ].compactMap { $0 }
    }
}

package protocol TypeMetadataProtocol: MetadataProtocol {
    static var descriptorOffset: Int { get }
}

package final class MetadataFinder<MachO: MachOSwiftSectionRepresentableWithCache & MachOOffsetConverter> {
    package let machO: MachO

    private var metadataOffsetByDescriptorOffset: [Int: Int] = [:]

    package init(machO: MachO) {
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

    package func metadata<Descriptor: TypeContextDescriptorProtocol, Metadata: TypeMetadataProtocol>(for descriptor: Descriptor) throws -> Metadata? {
        guard let offset = metadataOffsetByDescriptorOffset[descriptor.offset] else { return nil }
        return try machO.readWrapperElement(offset: offset - Metadata.descriptorOffset) as Metadata
    }
}
