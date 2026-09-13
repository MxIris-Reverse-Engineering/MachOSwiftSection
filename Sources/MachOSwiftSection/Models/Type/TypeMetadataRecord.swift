import Foundation
import MachOKit
import MachOBase

/// Mirrors `TargetTypeMetadataRecord` from
/// `swift/include/swift/ABI/Metadata.h:2720`. One entry per 4-byte slot of
/// `__swift5_types` / `__swift5_types2`.
///
/// In C++ the record is a union over two arms, both
/// `RelativeDirectPointerIntPair<…, TypeReferenceKind>` with identical
/// in-memory layout, so a single storage field is enough; the
/// `TypeReferenceKind` tag picks which arm to resolve at access time.
@LocatableLayoutWrapping
public struct TypeMetadataRecord: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let nominalTypeDescriptor: RelativeDirectPointerIntPair<ContextDescriptorWrapper, TypeReferenceKind>
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
    ///
    /// An indirect record whose slot is a **bind** also answers `nil`: the
    /// descriptor lives in another image and dyld fills the slot at load
    /// time, so offline there is nothing at the slot to read. Reading it
    /// anyway produced a descriptor at offset 0 whose kind is garbage, and
    /// the `invalidContextDescriptor` that threw took the whole `__swift5_types`
    /// list with it — the iOS 26.5 simulator's `libswiftSynchronization`
    /// registers a record for `libswiftCore/_$sSqMn` (`Swift.Optional`) and
    /// used to dump with no types at all.
    public func contextDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ContextDescriptorWrapper? {
        let fieldOffset = offset(of: \.nominalTypeDescriptor)
        let relativeOffset = layout.nominalTypeDescriptor.relativeOffset
        switch typeKind {
        case .directTypeDescriptor:
            let pointer = RelativeDirectPointer<ContextDescriptorWrapper>(relativeOffset: relativeOffset)
            return try pointer.resolve(from: fieldOffset, in: machO)
        case .indirectTypeDescriptor:
            if let machOFile = machO as? MachOFile, machOFile.resolveBind(fileOffset: fieldOffset + Int(relativeOffset)) != nil {
                return nil
            }
            let pointer = RelativeIndirectPointer<ContextDescriptorWrapper, Pointer<ContextDescriptorWrapper>>(relativeOffset: relativeOffset)
            return try pointer.resolve(from: fieldOffset, in: machO)
        case .directObjCClassName, .indirectObjCClass:
            return nil
        }
    }
    
    public func contextDescriptor<Context: ReadingContext>(in context: Context) throws -> ContextDescriptorWrapper? {
        let fieldOffset = offset(of: \.nominalTypeDescriptor)
        let relativeOffset = layout.nominalTypeDescriptor.relativeOffset
        switch typeKind {
        case .directTypeDescriptor:
            let pointer = RelativeDirectPointer<ContextDescriptorWrapper>(relativeOffset: relativeOffset)
            return try pointer.resolve(at: context.addressFromOffset(fieldOffset), in: context)
        case .indirectTypeDescriptor:
            let pointer = RelativeIndirectPointer<ContextDescriptorWrapper, Pointer<ContextDescriptorWrapper>>(relativeOffset: relativeOffset)
            return try pointer.resolve(at: context.addressFromOffset(fieldOffset), in: context)
        case .directObjCClassName, .indirectObjCClass:
            return nil
        }
    }
}
