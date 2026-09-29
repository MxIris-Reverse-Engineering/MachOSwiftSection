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
    func opaqueType(forNode node: Node, index: Int?) async -> String?
}
