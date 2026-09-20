import Demangling
import MachOKitExtensions
@_spi(Internals) import SwiftInspection
import SwiftThunkAnalysis

extension TypeDefinition {
    /// Marks the members that override an ObjC-inherited member (evolution
    /// proposal `objc-ancestor-override-recovery`). Only a class can; only a
    /// class with a static class object in `__objc_classlist` (a non-generic
    /// one) can be looked up; and only a class with ObjC methods of its own
    /// has anything to attribute — every other case leaves the members as
    /// they are. The verdicts come from `ObjCAncestorOverrides`, which asks
    /// the host's registered hierarchy provider first and the library's own
    /// reader second.
    ///
    /// Returns the table when one applied, so the caller can report it.
    @discardableResult
    package func applyObjCAncestorOverrides(in machO: some MachORepresentableWithCache) -> ObjCAncestorOverrideTable? {
        guard typeName.kind == .class else { return nil }
        // `materialize()` builds one transient tree per class indexed; the
        // qualified name is the same key the static layout engine and the
        // ObjC-side index derive from the class's runtime name.
        guard let qualifiedName = NodeTypeNaming.nominalQualifiedName(ofDemangledRoot: typeName.node.materialize()) else { return nil }
        guard let table = ObjCAncestorOverrides.table(forSwiftClassQualifiedName: qualifiedName, in: machO), !table.isEmpty else { return nil }
        ObjCAncestorOverrideApplication.apply(
            table,
            functions: &functions,
            variables: &variables,
            subscripts: &subscripts,
            staticFunctions: &staticFunctions,
            staticVariables: &staticVariables,
            staticSubscripts: &staticSubscripts,
            allocators: &allocators
        )
        return table
    }
}
