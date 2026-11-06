import Foundation
import MachOBase

public typealias ResolvableLocatableLayoutWrapper = LocatableLayoutWrapper & Resolvable

/// Makes a wrapper struct a `ResolvableLocatableLayoutWrapper`: generates the
/// three storage-level requirements of `LocatableLayoutWrapper` —
/// `var layout: Layout`, `let offset: Int` and `init(layout:offset:)` — and
/// adds whichever of `LocatableLayoutWrapper` and `Resolvable` the type does
/// not conform to yet.
///
///     @ResolvableLocatableLayoutWrapper
///     public struct MethodDescriptor {
///         public struct Layout: LayoutProtocol {
///             public let flags: MethodDescriptorFlags
///             public let implementation: RelativeDirectRawPointer
///         }
///     }
///
/// A wrapper declared as a protocol refining `ResolvableLocatableLayoutWrapper`
/// (`MetadataProtocol`, `ContextDescriptorProtocol`, …) keeps that protocol on
/// its declaration; the macro then adds no conformance.
///
/// Generated members take the host's own access level. A member the host
/// declares itself is left alone, with a warning saying so.
@attached(member, names: named(layout), named(offset), named(init))
@attached(extension, conformances: LocatableLayoutWrapper, Resolvable)
public macro ResolvableLocatableLayoutWrapper() = #externalMacro(module: "MachOMacros", type: "ResolvableLocatableLayoutWrapperMacro")
