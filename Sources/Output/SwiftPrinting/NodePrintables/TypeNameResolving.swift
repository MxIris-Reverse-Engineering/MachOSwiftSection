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

/// Expands an opaque return type (`some P`) from its descriptor's generic
/// requirements.
public protocol OpaqueTypeResolving: TypeNameResolving {
    func opaqueType(forNode node: Node, index: Int?) async -> String?
}
