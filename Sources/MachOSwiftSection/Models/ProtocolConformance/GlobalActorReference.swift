import Foundation
import MachOKit
import MachOFoundation

/// Trailing object of `TargetProtocolConformanceDescriptor` carrying the global
/// actor that isolates a conformance (e.g. `extension X: @MainActor P`).
///
/// Present iff `ProtocolConformanceFlags.hasGlobalActorIsolation` is set. Mirrors
/// `TargetGlobalActorReference` in the Swift 6.2+ ABI: a relative pointer to the
/// mangled actor type name followed by a relative pointer to the actor's
/// `GlobalActor` conformance descriptor. Only the type-name pointer is used when
/// rendering the attribute; the conformance pointer exists for runtime dispatch.
public struct GlobalActorReference: LocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let type: RelativeDirectPointer<MangledName>
        /// Relative pointer to the conformance descriptor that witnesses the actor's
        /// `GlobalActor` conformance. Stored as a raw offset because the dumper only
        /// needs the actor type name for attribute rendering.
        public let conformance: RelativeOffset
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension GlobalActorReference {
    public func typeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
        try layout.type.resolve(from: offset(of: \.type), in: machO)
    }

    public func typeName() throws -> MangledName {
        try layout.type.resolve(from: pointer(of: \.type))
    }
}

// MARK: - ReadingContext Support

extension GlobalActorReference {
    public func typeName<Context: ReadingContext>(in context: Context) throws -> MangledName {
        try layout.type.resolve(at: try context.addressFromOffset(offset(of: \.type)), in: context)
    }
}
