import SwiftInspection

extension ExtensionDefinition {
    /// The extension-side twin of `TypeDefinition.applyObjCAncestorOverrides`
    /// for an `@objc @implementation` class body (evolution proposal
    /// `objc-ancestor-override-recovery`): the class has no vtable at all, so
    /// the ObjC method table is the only place its overrides show. The caller
    /// supplies the table it looked up by the class's bare ObjC name — the
    /// same table serves the main body and any `@objc(Category)
    /// @implementation` extension of the class, since the linker merged the
    /// category's methods into the class object.
    @discardableResult
    package func applyObjCAncestorOverrides(_ table: ObjCAncestorOverrideTable) -> Int {
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
    }
}
