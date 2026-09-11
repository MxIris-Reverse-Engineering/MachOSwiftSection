/// Generates the three storage-level requirements of `LocatableLayoutWrapper`
/// — `var layout: Layout`, `let offset: Int` and `init(layout:offset:)`.
///
/// The conformance is not generated: keep the protocol on the declaration.
///
///     @LocatableLayoutWrapping
///     public struct MethodDescriptor: ResolvableLocatableLayoutWrapper {
///         public struct Layout: LayoutProtocol {
///             public let flags: MethodDescriptorFlags
///             public let implementation: RelativeDirectRawPointer
///         }
///     }
///
/// Generated members take the host's own access level. A member the host
/// declares itself is left alone, with a warning saying so.
@attached(member, names: named(layout), named(offset), named(init))
public macro LocatableLayoutWrapping() = #externalMacro(module: "MachOMacros", type: "LocatableLayoutWrappingMacro")
