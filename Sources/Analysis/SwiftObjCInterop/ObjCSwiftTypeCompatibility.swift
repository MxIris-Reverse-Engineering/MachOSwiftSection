import Foundation
@_spi(Internals) import Demangling
import SwiftInspection

/// Whether a Swift member's type can be the type of the Objective-C member it
/// is paired with by name (evolution proposal
/// `swift-first-imported-declarations`). It guards the name-only pairing of
/// an imported declaration's members, and it is the evidence that a Swift
/// property of the same name is another declaration — the one a header's
/// `NS_REFINED_FOR_SWIFT` leaves the plain name to.
///
/// Only a clear mismatch counts; whatever might bridge is compatible, so a
/// guess never refuses a pairing:
///
/// - an object (`@`, a block excluded) against a struct or an enum the
///   implementing module itself defines. A framework's own value type does
///   not bridge to an Objective-C object: `SceneHosting.ScenePresentationSettings`
///   cannot be what `-[SHScenePresentation settings]` returns. A value type
///   of another module may (`String`, `Data`, `UTType`), so it is not judged.
/// - a scalar (an integer, a floating-point number, `BOOL`) against a class or
///   an existential, which are always references.
package enum ObjCSwiftTypeCompatibility {
    /// Whether `swiftType` (a type node, `Optional` included) clearly cannot
    /// be `objcType`. `implementingModuleName` is the Swift module that
    /// implements the Objective-C member; without it no value type is judged.
    package static func isClearlyIncompatible(objcType: ObjCEncodedType, swiftType: Node, implementingModuleName: String?) -> Bool {
        let swiftType = unwrappingOptional(swiftType)
        if case .object = objcType {
            guard let implementingModuleName,
                  let nominal = NodeTypeNaming.unwrappedNominal(of: swiftType),
                  nominal.kind == .structure || nominal.kind == .enum
            else { return false }
            return moduleName(of: nominal) == implementingModuleName
        }
        if isScalar(objcType) {
            return isReference(swiftType)
        }
        return false
    }

    /// Whether any position of a method clearly mismatches: the return type
    /// or a parameter, compared where both sides have one. An initializer's
    /// result is its class on both sides and is not compared.
    package static func isClearlyIncompatible(objcMethodType: ObjCMethodTypeEncoding, swiftFunctionType: Node, comparesResult: Bool, implementingModuleName: String?) -> Bool {
        let swiftParameterTypes = parameterTypes(ofFunctionType: swiftFunctionType)
        if swiftParameterTypes.count == objcMethodType.parameterTypes.count {
            for (objcParameterType, swiftParameterType) in zip(objcMethodType.parameterTypes, swiftParameterTypes)
                where isClearlyIncompatible(objcType: objcParameterType, swiftType: swiftParameterType, implementingModuleName: implementingModuleName) {
                return true
            }
        }
        if comparesResult, let swiftResultType = resultType(ofFunctionType: swiftFunctionType) {
            return isClearlyIncompatible(objcType: objcMethodType.returnType, swiftType: swiftResultType, implementingModuleName: implementingModuleName)
        }
        return false
    }

    // MARK: - Swift type nodes

    /// The function type of a demangled member symbol: `Function`,
    /// `Allocator` or `Constructor` > `Type` > `FunctionType`.
    package static func functionType(ofDemangledMember root: Node) -> Node? {
        guard let entity = root.first(of: .function) ?? root.first(of: .allocator) ?? root.first(of: .constructor),
              let typeNode = entity.children.last(where: { $0.kind == .type })
        else { return nil }
        return typeNode.children.first { $0.kind == .functionType || $0.kind == .noEscapeFunctionType }
    }

    /// The declared type of a demangled property symbol: `Variable` > `Type`.
    package static func propertyType(ofDemangledMember root: Node) -> Node? {
        root.first(of: .variable)?.children.last { $0.kind == .type }
    }

    private static func parameterTypes(ofFunctionType functionType: Node) -> [Node] {
        guard let argumentTuple = functionType.children.first(where: { $0.kind == .argumentTuple }),
              let argumentType = argumentTuple.children.first(where: { $0.kind == .type }),
              let argument = argumentType.children.first
        else { return [] }
        guard argument.kind == .tuple else { return [argumentType] }
        return argument.children.compactMap { element in
            element.children.last { $0.kind == .type }
        }
    }

    private static func resultType(ofFunctionType functionType: Node) -> Node? {
        functionType.children.first { $0.kind == .returnType }?.children.first
    }

    private static func unwrappingOptional(_ node: Node) -> Node {
        var current = node
        while true {
            if current.kind == .type, let child = current.firstChild {
                current = child
                continue
            }
            if current.kind == .sugaredOptional, let child = current.firstChild {
                current = child
                continue
            }
            if current.kind == .boundGenericEnum,
               let nominal = current.firstChild.flatMap(NodeTypeNaming.unwrappedNominal),
               nominal.identifier == "Optional", moduleName(of: nominal) == "Swift",
               let typeList = current.children.first(where: { $0.kind == .typeList }),
               let wrapped = typeList.firstChild {
                current = wrapped
                continue
            }
            return current
        }
    }

    /// The module a nominal is declared in, through its enclosing types.
    private static func moduleName(of nominal: Node) -> String? {
        var context = nominal.firstChild
        while let current = context {
            if current.kind == .module {
                return current.text
            }
            context = current.firstChild
        }
        return nil
    }

    private static func isScalar(_ type: ObjCEncodedType) -> Bool {
        switch type {
        case .bool, .character, .unsignedCharacter, .short, .unsignedShort, .int, .unsignedInt,
             .long, .unsignedLong, .longLong, .unsignedLongLong, .float, .double, .longDouble:
            true
        default:
            false
        }
    }

    private static func isReference(_ node: Node) -> Bool {
        switch node.kind {
        case .class, .boundGenericClass, .protocolList, .protocolListWithClass, .protocolListWithAnyObject:
            true
        default:
            false
        }
    }
}
