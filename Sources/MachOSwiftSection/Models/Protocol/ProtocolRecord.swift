import Foundation
import MachOKit
import MachOFoundation

/// Mirrors `TargetProtocolRecord` from
/// `swift/include/swift/ABI/Metadata.h:2766`. One entry per 4-byte slot of
/// `__swift5_protos`.
///
/// The C++ declaration stores a single
/// `RelativeContextPointerIntPair<Runtime, bool, TargetProtocolDescriptor>`
/// (`MetadataRef.h:109` — a `RelativeIndirectablePointerIntPair` with
/// `nullable=true`). The low bit is the indirect flag handled by the pointer
/// itself; the next bit ("reserved for future use", see
/// `Metadata.h:2769`) is exposed via `Bit` and currently ignored by the
/// runtime (`MetadataLookup.cpp:821` only calls `getPointer()`).
public struct ProtocolRecord: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let `protocol`: RelativeIndirectablePointerIntPair<ProtocolDescriptor?, Bit, Pointer<ProtocolDescriptor?>>
    }

    public let offset: Int
    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension ProtocolRecord {
    public func protocolDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolDescriptor? {
        try layout.protocol.resolve(from: offset(of: \.protocol), in: machO)
    }
}

// MARK: - ReadingContext Support

extension ProtocolRecord {
    public func protocolDescriptor<Context: ReadingContext>(in context: Context) throws -> ProtocolDescriptor? {
        try layout.protocol.resolve(at: try context.addressFromOffset(offset(of: \.protocol)), in: context)
    }
}
