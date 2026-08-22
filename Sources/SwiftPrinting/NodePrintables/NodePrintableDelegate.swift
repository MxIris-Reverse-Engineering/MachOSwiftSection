import SwiftDeclaration
import Demangling
import Foundation

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

public protocol TypeNameResolvable: Sendable {
    func moduleName(forTypeName typeName: String) async -> String?
    func swiftName(forCName cName: String, category: CImportedTypeNameCategory) async -> String?
    func opaqueType(forNode node: Node, index: Int?) async -> String?
}

extension TypeNameResolvable {
    public func moduleName(forTypeName typeName: String) async -> String? { nil }
    public func swiftName(forCName cName: String, category: CImportedTypeNameCategory) async -> String? { nil }
    public func opaqueType(forNode node: Node, index: Int?) async -> String? { nil }
}

protocol NodePrintableDelegate: TypeNameResolvable, AnyObject {}
