import Foundation
import MachOKit
import MachOFoundation

extension MachOFile {
    public struct Swift {
        private let machOFile: MachOFile

        fileprivate init(machOFile: MachOFile) {
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

    public var typeContextDescriptors: [ContextDescriptorWrapper]? {
        return _readDescriptors(from: .__swift5_types, in: machOFile) + _readDescriptors(from: .__swift5_types2, in: machOFile)
    }

    public var associatedTypeDescriptors: [AssociatedTypeDescriptor]? {
        guard let section = _section(for: .__swift5_assocty, in: machOFile) else { return nil }
        do {
            var associatedTypeDescriptors: [AssociatedTypeDescriptor] = []
            let offset = if let cache = machOFile.cache {
                section.address - cache.mainCacheHeader.sharedRegionStart.cast()
            } else {
                section.offset
            }
            var currentOffset = offset
            let endOffset = offset + section.size
            while currentOffset < endOffset {
                let associatedTypeDescriptor: AssociatedTypeDescriptor = try machOFile.readElement(offset: currentOffset)
                currentOffset += associatedTypeDescriptor.size
                associatedTypeDescriptors.append(associatedTypeDescriptor)
            }
            return associatedTypeDescriptors
        } catch {
            return nil
        }
    }
}

extension MachOFile.Swift {
    private func _section(for swiftMachOSection: MachOSwiftSectionName, in machOFile: MachOFile) -> (any SectionProtocol)? {
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
        return swiftSection
    }

    private func _readDescriptors<Descriptor: Resolvable>(from swiftMachOSection: MachOSwiftSectionName, in machOFile: MachOFile) -> [Descriptor]? {
        guard let section = _section(for: swiftMachOSection, in: machOFile) else { return nil }
        return try? _readDescriptors(from: section, in: machOFile)
    }

    private func _readDescriptors<Descriptor: Resolvable>(from section: any SectionProtocol, in machO: MachOFile) throws -> [Descriptor] {
        let pointerSize: Int = MemoryLayout<RelativeDirectPointer<Descriptor>>.size
        let offset = if let cache = machO.cache {
            section.address - cache.mainCacheHeader.sharedRegionStart.cast()
        } else {
            section.offset
        }
        let data: [AnyLocatableLayoutWrapper<RelativeDirectPointer<Descriptor>>] = try machO.readElements(offset: offset, numberOfElements: section.size / pointerSize)

        return try data.map { try $0.layout.resolve(from: $0.offset, in: machO) }
    }
}

func + <Element>(lhs: [Element]?, rhs: [Element]?) -> [Element]? {
    guard let lhs = lhs else { return rhs ?? nil }
    guard let rhs = rhs else { return lhs }
    return lhs + rhs
}
