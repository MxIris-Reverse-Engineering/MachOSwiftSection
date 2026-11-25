import Demangling

/// The declaration category of a C-imported type reference, as the mangling
/// records it. A Swift-spelling lookup is only well-defined per category: an
/// ObjC protocol and class may share one C name (`NSObject`), and only the
/// protocol is renamed (`NSObjectProtocol`) — a category-blind lookup would
/// rewrite class references with the protocol's rename.
public enum CImportedTypeNameCategory: Sendable {
    case objcClass
    case objcProtocol
    case valueType
    case other

    public init(nodeKind: Node.Kind) {
        switch nodeKind {
        case .class:
            self = .objcClass
        case .protocol:
            self = .objcProtocol
        case .enum, .structure:
            self = .valueType
        default:
            self = .other
        }
    }
}

/// Marker for a resolver registrable with ``SwiftDeclarationPrinter``. Conform
/// to the role protocols below for the queries the resolver actually serves —
/// a resolver conforming to none of them is never consulted, and the roles
/// deliberately carry no default implementations, so a signature drift breaks
/// the conformer at compile time instead of silently unhooking it.
public protocol TypeNameResolving: Sendable {}

/// Resolves the real module of a type printed under a placeholder module
/// (`__C.NSString` → `Foundation`).
public protocol ModuleNameResolving: TypeNameResolving {
    func moduleName(forTypeName typeName: String) async -> String?
}

/// Resolves a C-imported identifier to its Swift spelling (APINotes renames,
/// the CF `Ref`-strip bridge rule), per declaration category.
public protocol CImportedNameResolving: TypeNameResolving {
    func swiftName(forCName cName: String, category: CImportedTypeNameCategory) async -> String?
}

/// Resolves the module that declares a Swift type now when its mangling
/// names the module the type was originally defined in
/// (`@_originallyDefinedIn`): `CoreGraphics.CGFloat` → `CoreFoundation`,
/// `SwiftUI.View` → `SwiftUICore` (evolution proposal
/// `moved-swift-type-modules`).
///
/// The printer asks for every module other than `__C` / `__ObjC`, by the
/// top-level type's name: a nested type follows its outermost type, as the
/// compiler's mangling does. `nil` keeps the mangling's module.
public protocol MovedTypeModuleResolving: TypeNameResolving {
    func declaringModuleName(ofMovedTypeNamed typeName: String, originallyDefinedIn originalModuleName: String) async -> String?
}

/// Expands an opaque return type (`some P`) from its descriptor's generic
/// requirements.
public protocol OpaqueTypeResolving: TypeNameResolving {
    /// The constraint text after `some`, spelled the way the rest of the print
    /// is: `spellingOptions` carries the spelling options the print uses — of
    /// `DemangleOptions.interfaceSpellingOptions`, `useModuleSelectors`
    /// (`Swift::Collection<Swift::Int>`) and `useExistentialAny` (an
    /// existential argument as `some Sequence<any Equatable>`). Every other
    /// option in it is ignored.
    func opaqueType(forNode node: Node, index: Int?, spellingOptions: DemangleOptions) async -> String?
}
