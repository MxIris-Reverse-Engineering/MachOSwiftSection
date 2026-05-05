import Foundation

open class Object {
    public init() {}

    open func instanceMethod() -> String {
        return "Hello, World!"
    }
}

/// Resilient base class used by SymbolTestsCore's
/// `ResilientClassFixtures.ResilientChild` to force a
/// `ResilientSuperclass` tail record on the child's class context
/// descriptor. The base must live in a DIFFERENT module so that the
/// child's layout cannot be statically computed by the compiler — only
/// then does `hasResilientSuperclass` fire on the child's descriptor.
///
/// `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` is enabled on
/// SymbolTestsHelper, so `ResilientBase` itself has resilient metadata
/// bounds. Subclasses outside this module therefore reference the
/// parent through a `RelativeDirectRawPointer` recorded in the
/// trailing-objects payload of their class descriptor.
open class ResilientBase {
    public init() {}
    public var counter: Int = 0
}
