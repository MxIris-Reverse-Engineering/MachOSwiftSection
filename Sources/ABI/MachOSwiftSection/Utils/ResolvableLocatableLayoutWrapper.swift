import Foundation
import MachOKit
import MachOBase

public typealias ResolvableLocatableLayoutWrapper = LocatableLayoutWrapper & Resolvable

/// Makes a wrapper struct a `ResolvableLocatableLayoutWrapper`: generates the
/// three storage-level requirements of `LocatableLayoutWrapper` —
/// `var layout: Layout`, `let offset: Int` and `init(layout:offset:)` — and an
/// extension conforming to every protocol of the hierarchy.
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
/// its declaration; the explicit conformances of the extension supersede the
/// ones it implies.
///
/// Generated members take the host's own access level. A member the host
/// declares itself is left alone, with a warning saying so.
///
/// The extension names every protocol of the hierarchy, not only the two at
/// its top, and names them on every host — the compiler's own list of missing
/// protocols is unreliable for this hierarchy (`ResolvableLocatableLayoutWrapperMacro`
/// explains why). Keep this list identical to the macro's
/// `conformanceHierarchy`.
@attached(member, names: named(layout), named(offset), named(init))
@attached(extension, conformances: LocatableLayoutWrapper, Resolvable, LayoutWrapper, Equatable, Sendable)
public macro ResolvableLocatableLayoutWrapper() = #externalMacro(module: "MachOMacros", type: "ResolvableLocatableLayoutWrapperMacro")
