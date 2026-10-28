import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Internals) import Demangling

/// The Swift nodes for the names the Objective-C runtime knows protocols and
/// classes by (evolution proposal `swift-declared-objc-protocols`): what an
/// `@objc` protocol's record and a class's protocol list spell, read back
/// the way Swift names them.
package enum ObjCRuntimeNames {
    /// A `Protocol` node for the protocol the Objective-C runtime knows as
    /// `runtimeName`: a Swift one by its `_TtP` mangling, or as `machO`
    /// declares it renamed; an imported one in `__C` under its Objective-C
    /// name, the way the compiler mangles it (`So8NSObject_p`). The Swift
    /// name an imported protocol goes by (`NSObjectProtocol`) is the type
    /// database's to give when the name prints, as for every `__C` name.
    /// Another image's renamed Swift protocol keeps its Objective-C name.
    package static func protocolNode(forRuntimeName runtimeName: String, in machO: some MachOSwiftSectionRepresentableWithCache) -> Node {
        if let protocolNode = swiftProtocolNode(forRuntimeName: runtimeName, in: machO) {
            return protocolNode
        }
        return Node.createTransient(kind: .protocol, children: [
            Node.createTransient(kind: .module, text: objcModule),
            Node.createTransient(kind: .identifier, text: runtimeName),
        ])
    }

    /// The node of a protocol declared in Swift — by its `_TtP` mangling, or
    /// renamed by `machO` — and `nil` for any other name.
    package static func swiftProtocolNode(forRuntimeName runtimeName: String, in machO: some MachOSwiftSectionRepresentableWithCache) -> Node? {
        if runtimeName.hasPrefix("_TtP"), let node = try? demangleAsNodeTransient(runtimeName), let protocolNode = node.first(of: .protocol) {
            return protocolNode
        }
        if let declared = SwiftDeclaredObjCProtocolIndex.shared.declaredProtocol(forRuntimeName: runtimeName, in: machO),
           let node = try? demangleAsNodeTransient(declared.mangledName), let protocolNode = node.first(of: .protocol) {
            return protocolNode
        }
        return nil
    }

    /// A `Class` node for the class the Objective-C runtime knows as
    /// `runtimeName`: a Swift one by its `_TtC` mangling or, renamed with
    /// `@objc(Name)`, through its descriptor; any other in `__C`.
    package static func classNode(forRuntimeName runtimeName: String, in machO: some MachOSwiftSectionRepresentableWithCache) -> Node {
        if let classNode = swiftClassNode(forRuntimeName: runtimeName, in: machO) {
            return classNode
        }
        return Node.createTransient(kind: .class, children: [
            Node.createTransient(kind: .module, text: objcModule),
            Node.createTransient(kind: .identifier, text: runtimeName),
        ])
    }

    /// The node of a class declared in Swift — by its `_TtC` mangling, or
    /// renamed by `machO` — and `nil` for any other name.
    package static func swiftClassNode(forRuntimeName runtimeName: String, in machO: some MachOSwiftSectionRepresentableWithCache) -> Node? {
        if runtimeName.hasPrefix("_Tt"), let node = try? demangleAsNodeTransient(runtimeName), let classNode = node.first(of: .class) {
            return classNode
        }
        if let descriptorOffset = SwiftClassObjectIndex.shared.classDescriptorOffset(forCustomRuntimeName: runtimeName, in: machO),
           let descriptor = try? ClassDescriptor.resolve(at: machO.context.addressFromOffset(descriptorOffset), in: machO.context),
           let contextNode = try? SymbolicDemangler.demangleContext(for: .type(.class(descriptor)), in: machO.context),
           let classNode = contextNode.first(of: .class) {
            return classNode
        }
        return nil
    }
}
