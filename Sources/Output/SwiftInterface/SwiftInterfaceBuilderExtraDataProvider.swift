import SwiftDeclaration
import SwiftIndexing
import SwiftPrinting
import Demangling

/// A builder-lifecycle hook: attached via `addExtraDataProvider(_:)`, its
/// `setup()` runs during `prepare()`. Resolver-ness is an orthogonal
/// capability — a provider that answers printer queries additionally conforms
/// to the `TypeNameResolving` role protocols (`ModuleNameResolving`,
/// `CImportedNameResolving`, `OpaqueTypeResolving`), and `addExtraDataProvider`
/// forwards it to the printer only then. A setup-only provider is a legitimate
/// conformer.
public protocol SwiftInterfaceBuilderExtraDataProvider: Sendable {
    func setup() async throws
}

extension SwiftInterfaceBuilderExtraDataProvider {
    public func setup() async throws {}
}
