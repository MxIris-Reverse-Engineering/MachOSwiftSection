import Foundation
import MachOKit
import MachOFoundation

/// Mirrors `TargetTypeMetadataRecord` from
/// `swift/include/swift/ABI/Metadata.h:2720`. One entry per 4-byte slot of
/// `__swift5_types` / `__swift5_types2`.
///
/// In C++ the record is a union over two arms, both
/// `RelativeDirectPointerIntPair<…, TypeReferenceKind>` with identical
/// in-memory layout, so a single storage field is enough; the
/// `TypeReferenceKind` tag picks which arm to resolve at access time.
public struct TypeMetadataRecord: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let nominalTypeDescriptor: RelativeDirectPointerIntPair<ContextDescriptorWrapper, TypeReferenceKind>
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension TypeMetadataRecord {
    public var typeKind: TypeReferenceKind {
        return layout.nominalTypeDescriptor.value
    }

    /// Resolves the referenced context descriptor, branching on
    /// `TypeReferenceKind` the same way Swift runtime does in
    /// `TargetTypeMetadataRecord::getContextDescriptor()`
    /// (`swift/include/swift/ABI/Metadata.h:2743`). ObjC kinds are never
    /// populated in this section (see the comment at Metadata.h:2751); return
    /// `nil` for them to mirror the runtime's `nullptr` fallback.
    public func contextDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ContextDescriptorWrapper? {
        let fieldOffset = offset(of: \.nominalTypeDescriptor)
        let relativeOffset = layout.nominalTypeDescriptor.relativeOffset
        switch typeKind {
        case .directTypeDescriptor:
            let pointer = RelativeDirectPointer<ContextDescriptorWrapper>(relativeOffset: relativeOffset)
            return try pointer.resolve(from: fieldOffset, in: machO)
        case .indirectTypeDescriptor:
            let pointer = RelativeIndirectPointer<ContextDescriptorWrapper, Pointer<ContextDescriptorWrapper>>(relativeOffset: relativeOffset)
            return try pointer.resolve(from: fieldOffset, in: machO)
        case .directObjCClassName, .indirectObjCClass:
            return nil
        }
    }
}
