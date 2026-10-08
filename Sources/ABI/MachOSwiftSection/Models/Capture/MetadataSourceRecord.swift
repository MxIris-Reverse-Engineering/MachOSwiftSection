import Foundation
import MachOKit
import MachOBase

/// One entry of a ``CaptureDescriptor``'s metadata source map: a generic
/// parameter (or other type the closure needs metadata for), paired with a
/// recipe for recovering that metadata at runtime from the context the
/// closure was handed.
///
/// A generic closure does not carry its type arguments as ordinary captures.
/// They arrive as bindings at the head of the context, or have to be dug out
/// of a captured value's own metadata, and the recipe for doing so is what
/// `mangledMetadataSource` encodes.
///
/// **That recipe is deliberately left unparsed here.** It is written in a
/// small expression language of its own (`swift/RemoteInspection`'s metadata
/// source grammar: closure bindings, reference captures, generic argument
/// projections), unrelated to Swift's type mangling, and reading it is a
/// separate piece of work — evolution proposal
/// `missing-abi-structures` scopes this batch to the descriptor's
/// skeleton. So both fields are handed back as raw ``MangledName`` values:
/// `mangledTypeName` genuinely is a mangled type and demangles, while
/// `mangledMetadataSource` is the untouched source expression.
///
/// Mirrors `swift::reflection::MetadataSourceRecord`
/// (`swift/RemoteInspection/Records.h`).
@LocatableLayoutWrapping
public struct MetadataSourceRecord: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let mangledTypeName: RelativeDirectPointer<MangledName>
        public let mangledMetadataSource: RelativeDirectPointer<MangledName>
    }
}

// MARK: - ReadingContext Support

extension MetadataSourceRecord {
    /// The type this entry supplies metadata for — a real mangled type name.
    public func mangledTypeName(in context: some ReadingContext) throws -> MangledName {
        try layout.mangledTypeName.resolve(at: try context.addressFromOffset(offset(of: \.mangledTypeName)), in: context)
    }

    /// The recipe for recovering that metadata, unparsed. See the type's
    /// documentation for why.
    public func mangledMetadataSource(in context: some ReadingContext) throws -> MangledName {
        try layout.mangledMetadataSource.resolve(at: try context.addressFromOffset(offset(of: \.mangledMetadataSource)), in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension MetadataSourceRecord {
    @available(*, deprecated, message: "Pass a ReadingContext: mangledTypeName(in: machO.context).")
    public func mangledTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try mangledTypeName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledMetadataSource(in: machO.context).")
    public func mangledMetadataSource(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try mangledMetadataSource(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledTypeName(in: .inProcess).")
    public func mangledTypeName() throws -> MangledName {
        try mangledTypeName(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledMetadataSource(in: .inProcess).")
    public func mangledMetadataSource() throws -> MangledName {
        try mangledMetadataSource(in: InProcessContext.shared)
    }
}
