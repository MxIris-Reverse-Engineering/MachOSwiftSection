import Demangling
import MachOKitExtensions
@_spi(Internals) import SwiftInspection
import SwiftThunkAnalysis

extension TypeDefinition {
    /// Ties the members to the class's ObjC method table (evolution proposals
    /// `objc-ancestor-override-recovery` and `objc-member-selector-recovery`):
    /// `@objc` on every member the table knows, `override` on those whose
    /// selector an ancestor also implements, the explicit selector on those
    /// the compiler would have named otherwise. Only a class can; only a
    /// class with a static class object in `__objc_classlist` (a non-generic
    /// one) can be looked up; and only a class with ObjC methods of its own
    /// has anything to attribute — every other case leaves the members as
    /// they are. The facts come from `ObjCMembers`, which asks the host's
    /// registered hierarchy provider first and the library's own reader
    /// second. All three evidence tiers run, the name-only one included;
    /// acting on that one is the consumer's call, taken through
    /// ``ResolvedObjCMemberFacts``.
    ///
    /// Returns the table when one applied, so the caller can report it.
    @discardableResult
    package func applyObjCMembers(in machO: some MachORepresentableWithCache) -> ObjCMemberTable? {
        guard typeName.kind == .class else { return nil }
        // `materialize()` builds one transient tree per class indexed; the
        // qualified name is the same key the static layout engine and the
        // ObjC-side index derive from the class's runtime name.
        guard let qualifiedName = NodeTypeNaming.nominalQualifiedName(ofDemangledRoot: typeName.node.materialize()) else { return nil }
        guard let table = ObjCMembers.table(forSwiftClassQualifiedName: qualifiedName, in: machO), !table.isEmpty else { return nil }
        ObjCMemberApplication.apply(
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
