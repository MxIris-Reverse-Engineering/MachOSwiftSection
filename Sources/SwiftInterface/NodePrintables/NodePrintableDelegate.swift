import Demangle
import Foundation

protocol NodePrintableDelegate: AnyObject {
    func moduleName(forTypeName typeName: String) -> String?
    func swiftName(forCName cName: String) -> String?
    func opaqueType(forNode node: Node, index: Int?) -> String?
}

extension NodePrintableDelegate {
    func moduleName(forTypeName typeName: String) -> String? { nil }
    func swiftName(forCName cName: String) -> String? { nil }
    func opaqueType(forNode node: Node, index: Int?) -> String? { nil }
}
