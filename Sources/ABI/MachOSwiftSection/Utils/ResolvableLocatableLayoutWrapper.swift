import Foundation
import MachOKit
import MachOBase

public typealias ResolvableLocatableLayoutWrapper = LocatableLayoutWrapper & Resolvable

/// Makes a wrapper struct a `ResolvableLocatableLayoutWrapper`: generates the
/// three storage-level requirements of `LocatableLayoutWrapper` —
/// `var layout: Layout`, `let offset: Int` and `init(layout:offset:)` — and
/// adds whichever protocols of the `ResolvableLocatableLayoutWrapper`
/// hierarchy the type does not conform to yet.
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
///
/// The extension names every protocol of the hierarchy, not only the two at
/// its top. A conformance the macro only implies (`LayoutWrapper` through
/// `LocatableLayoutWrapper`) was invisible to a static member reference
/// type-checked before the macro expanded: `TypeMetadataRecord.layoutSize`
/// failed with "requires that 'TypeMetadataRecord' conform to
/// 'LayoutWrapper'" in one file and compiled in the next.
@attached(member, names: named(layout), named(offset), named(init))
@attached(extension, conformances: LocatableLayoutWrapper, Resolvable, LayoutWrapper, Equatable, Sendable)
public macro ResolvableLocatableLayoutWrapper() = #externalMacro(module: "MachOMacros", type: "ResolvableLocatableLayoutWrapperMacro")
