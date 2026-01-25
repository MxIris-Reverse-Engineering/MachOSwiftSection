import Demangling
import Foundation

public protocol TypeNameResolvable: Sendable {
    func moduleName(forTypeName typeName: String) async -> String?
    func swiftName(forCName cName: String) async -> String?
    func opaqueType(forNode node: Node, index: Int?) async -> String?
}

extension TypeNameResolvable {
    public func moduleName(forTypeName typeName: String) async -> String? { nil }
    public func swiftName(forCName cName: String) async -> String? { nil }
    public func opaqueType(forNode node: Node, index: Int?) async -> String? { nil }
}

protocol NodePrintableDelegate: TypeNameResolvable, AnyObject {}
