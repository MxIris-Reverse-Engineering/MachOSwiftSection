import Foundation
import MachOKit
import MachOFoundation

extension MachOImage {
    public struct Swift {
        private let machOImage: MachOImage

        fileprivate init(machOImage: MachOImage) {
            self.machOImage = machOImage
        }
    }

    public var swift: Swift {
        .init(machOImage: self)
    }
}

extension MachOImage.Swift {
    public var protocolDescriptors: [ProtocolDescriptor] {
        get throws {
            return try _readDescriptors(from: .__swift5_protos, in: machOImage)
        }
    }

    public var protocolConformanceDescriptors: [ProtocolConformanceDescriptor] {
        get throws {
            return try _readDescriptors(from: .__swift5_proto, in: machOImage)
        }
    }

    public var typeContextDescriptors: [ContextDescriptorWrapper] {
        get throws {
            return try _readDescriptors(from: .__swift5_types, in: machOImage) + (try? _readDescriptors(from: .__swift5_types2, in: machOImage))
        }
    }

    public var associatedTypeDescriptors: [AssociatedTypeDescriptor] {
        get throws {
            let section = try machOImage.section(for: .__swift5_assocty)
            var associatedTypeDescriptors: [AssociatedTypeDescriptor] = []
            let vmaddrSlide = try required(machOImage.vmaddrSlide)
            let start = try required(UnsafeRawPointer(bitPattern: section.address + vmaddrSlide))
            let offset = start.int - machOImage.ptr.int
            var currentOffset = offset
            let endOffset = offset + section.size
            while currentOffset < endOffset {
                let associatedTypeDescriptor: AssociatedTypeDescriptor = try machOImage.readElement(offset: currentOffset)
                currentOffset += associatedTypeDescriptor.size
                associatedTypeDescriptors.append(associatedTypeDescriptor)
            }
            return associatedTypeDescriptors
        }
    }
}

extension MachOImage.Swift {
    private func _readDescriptors<Descriptor: Resolvable>(from swiftMachOSection: MachOSwiftSectionName, in machO: MachOImage) throws -> [Descriptor] {
        let section = try machO.section(for: swiftMachOSection)
        
        let vmaddrSlide = try required(machO.vmaddrSlide)
        let start = try required(UnsafeRawPointer(bitPattern: section.address + vmaddrSlide))

        let offset = start.int - machO.ptr.int

        let pointerSize: Int = MemoryLayout<RelativeDirectPointer<Descriptor>>.size

        let data: [AnyLocatableLayoutWrapper<RelativeDirectPointer<Descriptor>>] = try machO.readElements(offset: offset, numberOfElements: section.size / pointerSize)

        return try data.map { try $0.layout.resolve(from: $0.offset, in: machO) }
    }
}
