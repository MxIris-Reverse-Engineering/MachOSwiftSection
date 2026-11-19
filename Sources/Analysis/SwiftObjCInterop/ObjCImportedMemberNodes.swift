import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Internals) import Demangling

/// The declaration node of an Objective-C member as Swift imports it, shaped
/// like the member symbol the compiler would have demangled to — `Global >
/// Function`, `Global > Static > Getter > Variable`, `Global > Allocator`,
/// `Global > Getter > Subscript` — so the member printers print it as they
/// print any other (evolution proposals `swift-declared-objc-protocols` and
/// `objc-imported-declarations`). Shared by a protocol's requirements and a
/// class's or category's members; `contextNode` is the `Protocol` or `Class`
/// node the member is declared on.
package struct ObjCImportedMemberNodes<MachO: MachOSwiftSectionRepresentableWithCache> {
    package let types: ObjCImportedTypes<MachO>

    package init(machO: MachO) {
        self.types = ObjCImportedTypes(machO: machO)
    }

    /// A property named `name` of type `type`.
    package func propertyNode(contextNode: Node, name: String, type: ObjCEncodedType, isClassMember: Bool) -> Node {
        let variable = Node.createTransient(kind: .variable, children: [
            contextNode,
            Node.createTransient(kind: .identifier, text: name),
            types.typeNode(type, position: .topLevel),
        ])
        return Self.global(Node.createTransient(kind: .getter, child: variable), isStatic: isClassMember)
    }

    /// The subscript `objectAtIndexedSubscript:` or `objectForKeyedSubscript:`
    /// imports as; `nil` when the encoding has no index parameter.
    package func subscriptNode(contextNode: Node, methodType: ObjCMethodTypeEncoding, isClassMember: Bool) -> Node? {
        guard let indexType = methodType.parameterTypes.first else { return nil }
        let functionType = Node.createTransient(kind: .functionType, children: [
            Node.createTransient(kind: .argumentTuple, child: types.typeNode(indexType, position: .topLevel)),
            Node.createTransient(kind: .returnType, child: types.typeNode(methodType.returnType, position: .topLevel)),
        ])
        let subscriptNode = Node.createTransient(kind: .subscript, children: [
            contextNode,
            Node.createTransient(kind: .labelList),
            Node.createTransient(kind: .type, child: functionType),
        ])
        return Self.global(Node.createTransient(kind: .getter, child: subscriptNode), isStatic: isClassMember)
    }

    /// A method or an initializer named `name`: an `Allocator` for an
    /// initializer — a factory method's included — a `Function` otherwise.
    /// An initializer returns `instancetype` of unknown nullability, `init!`.
    package func methodNode(contextNode: Node, name: ObjCImporterNaming.ImportedName, methodType: ObjCMethodTypeEncoding, isClassMember: Bool) -> Node {
        let isInitializer = name.kind == .initializer || name.kind == .factoryInitializer
        var parameterTypes = name.parameterIndices.map { methodType.parameterTypes.indices.contains($0) ? methodType.parameterTypes[$0] : .unknown }
        // An initializer with no argument whose first piece goes on past
        // `init` (`initForIncrementalLoad`) takes a label but no parameter:
        // the importer gives it a `()` one, `init(forIncrementalLoad: ())`.
        if parameterTypes.count < name.argumentLabels.count {
            parameterTypes += Array(repeating: .void, count: name.argumentLabels.count - parameterTypes.count)
        }
        let resultType: Node
        if isInitializer {
            resultType = ObjCImportedTypes<MachO>.initializerResultTypeNode
        } else {
            switch name.errorConvention {
            case .booleanResult: resultType = types.typeNode(.void, position: .topLevel)
            case .nonNilResult: resultType = types.typeNode(methodType.returnType, position: .nonOptional)
            case nil: resultType = types.typeNode(methodType.returnType, position: .topLevel)
            }
        }
        var functionTypeChildren: [Node] = []
        if name.errorConvention != nil {
            functionTypeChildren.append(Node.createTransient(kind: .throwsAnnotation))
        }
        functionTypeChildren.append(Node.createTransient(kind: .argumentTuple, child: ObjCImportedTypes<MachO>.type(Node.createTransient(kind: .tuple, children: parameterTypes.map {
            Node.createTransient(kind: .tupleElement, child: types.typeNode($0, position: .topLevel))
        }))))
        functionTypeChildren.append(Node.createTransient(kind: .returnType, child: resultType))
        var declarationChildren: [Node] = [contextNode]
        if !isInitializer {
            declarationChildren.append(Node.createTransient(kind: .identifier, text: name.baseName))
        }
        if !name.argumentLabels.isEmpty {
            declarationChildren.append(Node.createTransient(kind: .labelList, children: name.argumentLabels.map {
                $0.isEmpty ? Node.createTransient(kind: .firstElementMarker) : Node.createTransient(kind: .identifier, text: $0)
            }))
        }
        declarationChildren.append(Node.createTransient(kind: .type, child: Node.createTransient(kind: .functionType, children: functionTypeChildren)))
        let declaration = Node.createTransient(kind: isInitializer ? .allocator : .function, children: declarationChildren)
        // An initializer is never a class member, a factory method's included.
        return Self.global(declaration, isStatic: isClassMember && !isInitializer)
    }

    private static func global(_ declaration: Node, isStatic: Bool) -> Node {
        Node.createTransient(kind: .global, child: isStatic ? Node.createTransient(kind: .static, child: declaration) : declaration)
    }
}
