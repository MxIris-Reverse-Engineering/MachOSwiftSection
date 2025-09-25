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

    public var swift: Swift {
        .init(machO: self)
    }
}

extension MachOFile.Swift: SwiftSectionRepresentable {
    public var types: [TypeWrapper] {
        get throws {
            var results: [TypeWrapper] = []
            let typeContextDescriptors = try typeContextDescriptors
            for typeContextDescriptor in typeContextDescriptors {
                switch typeContextDescriptor {
                case let .enum(descriptor):
                    try results.append(.enum(.init(descriptor: descriptor, in: machO)))
                case let .struct(descriptor):
                    try results.append(.struct(.init(descriptor: descriptor, in: machO)))
                case let .class(descriptor):
                    try results.append(.class(.init(descriptor: descriptor, in: machO)))
                }
            }
            return results
        }
    }

    public var protocols: [Protocol] {
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
            return try _readRelativeDescriptors(from: .__swift5_types, in: machO) + (try? _readRelativeDescriptors(from: .__swift5_types2, in: machO))
        }
    }

    public var typeContextDescriptors: [TypeContextDescriptorWrapper] {
        get throws {
            return try _readRelativeDescriptors(from: .__swift5_types, in: machO) + (try? _readRelativeDescriptors(from: .__swift5_types2, in: machO))
        }
    }

    public var protocolDescriptors: [ProtocolDescriptor] {
        get throws {
            return try _readRelativeDescriptors(from: .__swift5_protos, in: machO)
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
}

extension MachOFile.Swift {
    private func _readDescriptors<Descriptor: TopLevelDescriptor>(from swiftMachOSection: MachOSwiftSectionName, in machO: MachOFile) throws -> [Descriptor] {
        let section = try machO.section(for: swiftMachOSection)
        var descriptors: [Descriptor] = []
        let offset = if let cache = machO.cache {
            section.address - cache.mainCacheHeader.sharedRegionStart.cast()
        } else {
            section.offset
        }
        var currentOffset = offset
        let endOffset = offset + section.size
        while currentOffset < endOffset {
            let descriptor: Descriptor = try machO.readWrapperElement(offset: currentOffset)
            currentOffset += descriptor.actualSize
            descriptors.append(descriptor)
        }
        return descriptors
    }

    private func _readRelativeDescriptors<Descriptor: Resolvable>(from swiftMachOSection: MachOSwiftSectionName, in machO: MachOFile) throws -> [Descriptor] {
        let section = try machO.section(for: swiftMachOSection)
        let pointerSize: Int = MemoryLayout<RelativeDirectPointer<Descriptor>>.size
        let offset = if let cache = machO.cache {
            section.address - cache.mainCacheHeader.sharedRegionStart.cast()
        } else {
            section.offset
        }
        let data: [AnyLocatableLayoutWrapper<RelativeDirectPointer<Descriptor>>] = try machO.readWrapperElements(offset: offset, numberOfElements: section.size / pointerSize)
        return data.compactMap { try? $0.layout.resolve(from: $0.offset, in: machO) }
    }
}

extension RelativeDirectPointer: LayoutProtocol {}
