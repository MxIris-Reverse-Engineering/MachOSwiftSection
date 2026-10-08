import SwiftInspection

extension ExtensionDefinition {
    /// The extension-side twin of `TypeDefinition.applyObjCMembers` (evolution
    /// proposals `objc-ancestor-override-recovery` and
    /// `objc-member-selector-recovery`), for an `@objc @implementation` class
    /// body — the class has no vtable at all, so the ObjC method table is the
    /// only place its members show — and for a Swift extension whose `@objc`
    /// members compiled to a category. The caller supplies the table it looked
    /// up by the class's name — the same table serves the main body and any
    /// `@objc(Category) @implementation` extension of the class, since the
    /// linker merged the category's methods into the class object, and the
    /// library's reader folds `__objc_catlist` in for the rest.
    @discardableResult
    package func applyObjCMembers(_ table: ObjCMemberTable) -> Int {
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
    }
}
