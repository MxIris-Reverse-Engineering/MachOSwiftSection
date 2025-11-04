import Demangling
import Foundation

protocol NodePrintableDelegate: AnyObject {
    func moduleName(forTypeName typeName: String) async -> String?
    func swiftName(forCName cName: String) async -> String?
    func opaqueType(forNode node: Node, index: Int?) async -> String?
}

extension NodePrintableDelegate {
    func moduleName(forTypeName typeName: String) async -> String? { nil }
    func swiftName(forCName cName: String) async -> String? { nil }
    func opaqueType(forNode node: Node, index: Int?) async -> String? { nil }
}
