import Foundation
import MachOKit
import MachOFoundation

extension MachOFile {
    public struct Swift {
        private let machO: MachOFile

        fileprivate init(machO: MachOFile) {
            self.machO = machO
        }
    }

    public var swift: Swift { .init(machO: self) }
}

extension MachOFile.Swift: SwiftSectionRepresentable {
    public var types: [TypeContextWrapper] {
        get throws {
            try typeContextDescriptors.map { try TypeContextWrapper.forTypeContextDescriptorWrapper($0, in: machO) }
        }
    }

    public var protocols: [`Protocol`] {
        get throws {
            try protocolDescriptors.map { try Protocol(descriptor: $0, in: machO) }
        }
    }

    public var protocolConformances: [ProtocolConformance] {
        get throws {
            try protocolConformanceDescriptors.map { try ProtocolConformance(descriptor: $0, in: machO) }
        }
    }

    public var associatedTypes: [AssociatedType] {
        get throws {
            try associatedTypeDescriptors.map { try AssociatedType(descriptor: $0, in: machO) }
        }
    }

    public var builtinTypes: [BuiltinType] {
        get throws {
            try builtinTypeDescriptors.map { try BuiltinType(descriptor: $0, in: machO) }
        }
    }

    public var contextDescriptors: [ContextDescriptorWrapper] {
        get throws {
            return try _readTypeMetadataRecords(from: .__swift5_types, in: machO) + (try? _readTypeMetadataRecords(from: .__swift5_types2, in: machO))
        }
    }

    public var typeContextDescriptors: [TypeContextDescriptorWrapper] {
        get throws {
            return try contextDescriptors.compactMap { $0.typeContextDescriptorWrapper }
        }
    }

    public var protocolDescriptors: [ProtocolDescriptor] {
        get throws {
            return try _readProtocolRecords(from: .__swift5_protos, in: machO)
        }
    }

    public var protocolConformanceDescriptors: [ProtocolConformanceDescriptor] {
        get throws {
            return try _readRelativeDescriptors(from: .__swift5_proto, in: machO)
        }
    }

    public var associatedTypeDescriptors: [AssociatedTypeDescriptor] {
        get throws {
            return try _readDescriptors(from: .__swift5_assocty, in: machO)
        }
    }

    public var builtinTypeDescriptors: [BuiltinTypeDescriptor] {
        get throws {
            return try _readDescriptors(from: .__swift5_builtin, in: machO)
        }
    }

    public var multiPayloadEnumDescriptors: [MultiPayloadEnumDescriptor] {
        get throws {
            return try _readDescriptors(from: .__swift5_mpenum, in: machO)
        }
    }
}

extension MachOFile.Swift {
    private func _sectionOffsetAndSize(of swiftMachOSection: MachOSwiftSectionName, in machO: MachOFile) throws -> (offset: Int, size: Int) {
        let section = try machO.section(for: swiftMachOSection)
        let offset = if let cache = machO.cache {
            section.address - cache.mainCacheHeader.sharedRegionStart.cast()
        } else {
            section.offset
        }
        return (offset, section.size)
    }

    private func _readDescriptors<Descriptor: TopLevelDescriptor>(from swiftMachOSection: MachOSwiftSectionName, in machO: MachOFile) throws -> [Descriptor] {
        let (offset, size) = try _sectionOffsetAndSize(of: swiftMachOSection, in: machO)
        var descriptors: [Descriptor] = []
        var currentOffset = offset
        let endOffset = offset + size
        while currentOffset < endOffset {
            let descriptor: Descriptor = try machO.readWrapperElement(offset: currentOffset)
            currentOffset += descriptor.actualSize
            descriptors.append(descriptor)
        }
        return descriptors
    }

    private func _readRelativeDescriptors<Descriptor: Resolvable>(from swiftMachOSection: MachOSwiftSectionName, in machO: MachOFile) throws -> [Descriptor] {
        let (offset, size) = try _sectionOffsetAndSize(of: swiftMachOSection, in: machO)
        let pointerSize: Int = MemoryLayout<RelativeDirectPointer<Descriptor>>.size
        let data: [AnyLocatableLayoutWrapper<RelativeDirectPointer<Descriptor>>] = try machO.readWrapperElements(offset: offset, numberOfElements: size / pointerSize)
        return try data.map { try $0.layout.resolve(from: $0.offset, in: machO) }
    }

    private func _readTypeMetadataRecords(from swiftMachOSection: MachOSwiftSectionName, in machO: MachOFile) throws -> [ContextDescriptorWrapper] {
        let (offset, size) = try _sectionOffsetAndSize(of: swiftMachOSection, in: machO)
        let recordSize = MemoryLayout<TypeMetadataRecord.Layout>.size
        let records: [TypeMetadataRecord] = try machO.readWrapperElements(offset: offset, numberOfElements: size / recordSize)
        return try records.compactMap { try $0.contextDescriptor(in: machO) }
    }

    private func _readProtocolRecords(from swiftMachOSection: MachOSwiftSectionName, in machO: MachOFile) throws -> [ProtocolDescriptor] {
        let (offset, size) = try _sectionOffsetAndSize(of: swiftMachOSection, in: machO)
        let recordSize = MemoryLayout<ProtocolRecord.Layout>.size
        let records: [ProtocolRecord] = try machO.readWrapperElements(offset: offset, numberOfElements: size / recordSize)
        return try records.compactMap { try $0.protocolDescriptor(in: machO) }
    }
}

extension RelativeDirectPointer: LayoutProtocol {}
