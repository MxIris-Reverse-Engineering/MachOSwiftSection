import Demangling

/// The aggregate query surface the node printers ask their answers from.
///
/// Deliberately fat on this, the consumer side: ``SwiftDeclarationPrinter`` is
/// the sole conformer and genuinely serves every query, fanning each one out
/// to the role-scoped resolvers registered with it (see `TypeNameResolving`
/// and the role protocols beside it for the provider side).
protocol NodePrintableDelegate: AnyObject, Sendable {
    func moduleName(forTypeName typeName: String) async -> String?
    func swiftName(forCName cName: String, category: CImportedTypeNameCategory) async -> String?
    func opaqueType(forNode node: Node, index: Int?, usesModuleSelectors: Bool) async -> String?
    /// Whether what `opaqueType(forNode:index:)` supplies is to be marked as
    /// visible only with opaque type resolution on (see
    /// `SwiftDeclarationPrintConfiguration.marksOptionalContent`).
    var marksOptionalContent: Bool { get }
    /// Whether names are qualified with SE-0491 module selectors (see
    /// `SwiftDeclarationPrintConfiguration.usesModuleSelectors`). A printer
    /// reads it once, when it is created.
    var usesModuleSelectors: Bool { get }
}
