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

extension MachOFile.Swift: SwiftSectionRepresentable {
    public var protocolDescriptors: [ProtocolDescriptor] {
        get throws {
            return try _readRelativeDescriptors(from: .__swift5_protos, in: machOFile)
        }
    }

    public var protocolConformanceDescriptors: [ProtocolConformanceDescriptor] {
        get throws {
            return try _readRelativeDescriptors(from: .__swift5_proto, in: machOFile)
        }
    }

    public var typeContextDescriptors: [ContextDescriptorWrapper] {
        get throws {
            return try _readRelativeDescriptors(from: .__swift5_types, in: machOFile) + (try? _readRelativeDescriptors(from: .__swift5_types2, in: machOFile))
        }
    }

    public var associatedTypeDescriptors: [AssociatedTypeDescriptor] {
        get throws {
            return try _readDescriptors(from: .__swift5_assocty, in: machOFile)
        }
    }

    public var builtinTypeDescriptors: [BuiltinTypeDescriptor] {
        get throws {
            return try _readDescriptors(from: .__swift5_builtin, in: machOFile)
        }
    }
}

extension MachOFile.Swift {
    private func _readDescriptors<Descriptor: TopLevelDescriptor>(from swiftMachOSection: MachOSwiftSectionName, in machO: MachOFile) throws -> [Descriptor] {
        let section = try machOFile.section(for: swiftMachOSection)
        var descriptors: [Descriptor] = []
        let offset = if let cache = machOFile.cache {
            section.address - cache.mainCacheHeader.sharedRegionStart.cast()
        } else {
            section.offset
        }
        var currentOffset = offset
        let endOffset = offset + section.size
        while currentOffset < endOffset {
            let descriptor: Descriptor = try machOFile.readWrapperElement(offset: currentOffset)
            currentOffset += descriptor.actualSize
            descriptors.append(descriptor)
        }
        return descriptors
    }

    private func _readRelativeDescriptors<Descriptor: Resolvable>(from swiftMachOSection: MachOSwiftSectionName, in machO: MachOFile) throws -> [Descriptor] {
        let section = try machOFile.section(for: swiftMachOSection)
        let pointerSize: Int = MemoryLayout<RelativeDirectPointer<Descriptor>>.size
        let offset = if let cache = machO.cache {
            section.address - cache.mainCacheHeader.sharedRegionStart.cast()
        } else {
            section.offset
        }
        let data: [AnyLocatableLayoutWrapper<RelativeDirectPointer<Descriptor>>] = try machO.readWrapperElements(offset: offset, numberOfElements: section.size / pointerSize)
        return try data.map { try $0.layout.resolve(from: $0.offset, in: machO) }
    }
}
