import Demangle
import Foundation

protocol InterfaceNodePrinterDelegate: AnyObject {
    func moduleName(forTypeName typeName: String) -> String?
    func swiftName(forCName cName: String) -> String?
    func opaqueType(forNode node: Node) -> String?
}
