import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import MachOCaches

/// Maps a metadata accessor function's offset back to the type descriptor it
/// belongs to.
///
/// Needed because one of the thunk shapes answers with a *call* rather than an
/// address: `cbz` splits into two branches and each calls the accessor of the
/// type that branch yields. The accessor carries no symbol in a stripped
/// framework, so the way back to a name is the descriptor that points **at**
/// it — `TypeContextDescriptor.accessFunctionPtr`.
///
/// Built by one sweep over `__swift5_types` and cached per image, because a
/// single dumped image can hit several thunks (SwiftUI: 14 records over 3
/// thunks) and the sweep is the expensive half.
package final class MetadataAccessorIndex: Sendable {
    private let descriptorOffsetsByAccessorOffset: [Int: Int]

    private init(descriptorOffsetsByAccessorOffset: [Int: Int]) {
        self.descriptorOffsetsByAccessorOffset = descriptorOffsetsByAccessorOffset
    }

    /// The offset of the type descriptor whose metadata accessor lives at
    /// `accessorOffset`, if any.
    package func descriptorOffset(forAccessorOffset accessorOffset: Int) -> Int? {
        descriptorOffsetsByAccessorOffset[accessorOffset]
    }

    package static func index(for machO: MachOFile) -> MetadataAccessorIndex {
        cache.storage(in: machO) { machO in build(for: machO) } ?? MetadataAccessorIndex(descriptorOffsetsByAccessorOffset: [:])
    }

    private static let cache = SharedCache<MetadataAccessorIndex>()

    private static func build(for machO: MachOFile) -> MetadataAccessorIndex {
        var descriptorOffsetsByAccessorOffset: [Int: Int] = [:]
        guard let typeDescriptors = try? machO.swift.typeContextDescriptors else {
            return MetadataAccessorIndex(descriptorOffsetsByAccessorOffset: [:])
        }
        for wrapper in typeDescriptors {
            let accessorOffsetAndDescriptorOffset: (accessor: Int, descriptor: Int)?
            switch wrapper {
            case .struct(let structDescriptor):
                accessorOffsetAndDescriptorOffset = accessorOffset(of: structDescriptor).map { ($0, structDescriptor.offset) }
            case .enum(let enumDescriptor):
                accessorOffsetAndDescriptorOffset = accessorOffset(of: enumDescriptor).map { ($0, enumDescriptor.offset) }
            case .class(let classDescriptor):
                accessorOffsetAndDescriptorOffset = accessorOffset(of: classDescriptor).map { ($0, classDescriptor.offset) }
            }
            guard let accessorOffsetAndDescriptorOffset else { continue }
            // First wins: two descriptors sharing one accessor would be an
            // ambiguity this index cannot resolve, and overwriting would make
            // which one you get depend on section order.
            if descriptorOffsetsByAccessorOffset[accessorOffsetAndDescriptorOffset.accessor] == nil {
                descriptorOffsetsByAccessorOffset[accessorOffsetAndDescriptorOffset.accessor] = accessorOffsetAndDescriptorOffset.descriptor
            }
        }
        return MetadataAccessorIndex(descriptorOffsetsByAccessorOffset: descriptorOffsetsByAccessorOffset)
    }

    /// Resolves the descriptor's relative accessor pointer to an offset.
    ///
    /// Mirrors `TypeContextDescriptorProtocol.metadataAccessorFunction(in:)`'s
    /// arithmetic, which is in-process only because it needs a loaded image to
    /// form a function pointer — the *offset* it computes on the way is
    /// exactly what an offline lookup needs.
    private static func accessorOffset<Descriptor: TypeContextDescriptorProtocol>(of descriptor: Descriptor) -> Int? {
        let relativePointer = descriptor.layout.accessFunctionPtr
        guard relativePointer.isValid else { return nil }
        return relativePointer.resolveDirectOffset(from: descriptor.offset + descriptor.layout.offset(of: .accessFunctionPtr))
    }
}
