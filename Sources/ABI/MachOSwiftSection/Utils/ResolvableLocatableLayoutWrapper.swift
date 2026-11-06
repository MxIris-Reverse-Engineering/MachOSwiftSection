import Foundation
import MachOKit
import MachOBase

public typealias ResolvableLocatableLayoutWrapper = LocatableLayoutWrapper & Resolvable

/// Makes a wrapper struct a `ResolvableLocatableLayoutWrapper`: generates the
/// three storage-level requirements of `LocatableLayoutWrapper` —
/// `var layout: Layout`, `let offset: Int` and `init(layout:offset:)` — and
/// adds whichever protocols of the hierarchy the type does not conform to yet.
///
///     import MachOKit
///     import MachOBase
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
/// `conformances:` names every protocol of the hierarchy, not only the two at
/// its top: with `LayoutWrapper` merely implied by `LocatableLayoutWrapper`,
/// `TypeMetadataRecord.layoutSize` failed with "requires that
/// 'TypeMetadataRecord' conform to 'LayoutWrapper'" in one file while the same
/// line compiled in another (Swift 6.3). The expansion therefore names
/// `LayoutWrapper`, which only MachOKit exports: **a file using the macro must
/// `import MachOKit`**, or the expansion fails with "cannot find type
/// 'LayoutWrapper' in scope".
@attached(member, names: named(layout), named(offset), named(init))
@attached(extension, conformances: LocatableLayoutWrapper, Resolvable, LayoutWrapper, Equatable, Sendable)
public macro ResolvableLocatableLayoutWrapper() = #externalMacro(module: "MachOMacros", type: "ResolvableLocatableLayoutWrapperMacro")
