public final class Node: @unchecked Sendable {
    public let kind: Kind
    public let contents: Contents
    public private(set) weak var parent: Node?
    public private(set) var children: [Node]

    public enum Contents: Hashable, Sendable {
        case none
        case index(UInt64)
        case name(String)

        public var hasName: Bool {
            name != nil
        }

        public var name: String? {
            switch self {
            case .none:
                return nil
            case .index:
                return nil
            case .name(let string):
                return string
            }
        }
    }

    public init(kind: Kind, contents: Contents = .none, children: [Node] = []) {
        self.kind = kind
        self.children = children
        self.contents = contents
        for child in children {
            child.parent = self
        }
    }

    package convenience init(kind: Kind, child: Node) {
        self.init(kind: kind, contents: .none, children: [child])
    }

    package convenience init(typeWithChildKind: Kind, childChild: Node) {
        self.init(kind: .type, contents: .none, children: [Node(kind: typeWithChildKind, children: [childChild])])
    }

    package convenience init(typeWithChildKind: Kind, childChildren: [Node]) {
        self.init(kind: .type, contents: .none, children: [Node(kind: typeWithChildKind, children: childChildren)])
    }

    package convenience init(swiftStdlibTypeKind: Kind, name: String) {
        self.init(kind: .type, contents: .none, children: [Node(kind: swiftStdlibTypeKind, children: [
            Node(kind: .module, contents: .name(stdlibName)),
            Node(kind: .identifier, contents: .name(name)),
        ])])
    }

    package convenience init(swiftBuiltinType: Kind, name: String) {
        self.init(kind: .type, children: [Node(kind: swiftBuiltinType, contents: .name(name))])
    }

    public var text: String? {
        switch contents {
        case .name(let s): return s
        default: return nil
        }
    }

    public var index: UInt64? {
        switch contents {
        case .index(let i): return i
        default: return nil
        }
    }

    public var isProtocol: Bool {
        switch kind {
        case .type: return children.first?.isProtocol ?? false
        case .protocol,
             .protocolSymbolicReference,
             .objectiveCProtocolSymbolicReference: return true
        default: return false
        }
    }

    package func changeChild(_ newChild: Node?, atIndex: Int) -> Node {
        guard children.indices.contains(atIndex) else { return self }

        var modifiedChildren = children
        if let nc = newChild {
            modifiedChildren[atIndex] = nc
        } else {
            modifiedChildren.remove(at: atIndex)
        }
        return Node(kind: kind, contents: contents, children: modifiedChildren)
    }

    package func changeKind(_ newKind: Kind, additionalChildren: [Node] = []) -> Node {
        if case .name(let text) = contents {
            return Node(kind: newKind, contents: .name(text), children: children + additionalChildren)
        } else if case .index(let i) = contents {
            return Node(kind: newKind, contents: .index(i), children: children + additionalChildren)
        } else {
            return Node(kind: newKind, contents: .none, children: children + additionalChildren)
        }
    }

    public func addChild(_ newChild: Node) {
        newChild.parent = self
        children.append(newChild)
    }

    public func removeChild(at index: Int) {
        guard children.indices.contains(index) else { return }
        children.remove(at: index)
    }

    public func insertChild(_ newChild: Node, at index: Int) {
        guard index >= 0, index <= children.count else { return }
        newChild.parent = self
        children.insert(newChild, at: index)
    }

    public func addChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child.parent = self
        }
        children.append(contentsOf: newChildren)
    }

    public func setChildren(_ newChildren: [Node]) {
        for child in newChildren {
            child.parent = self
        }
        children = newChildren
    }

    public func setChild(_ child: Node, at index: Int) {
        guard children.indices.contains(index) else { return }
        child.parent = self
        children[index] = child
    }

    public func reverseChildren() {
        children.reverse()
    }
}

extension Node {
    public var isSimpleType: Bool {
        switch kind {
        case .associatedType: fallthrough
        case .associatedTypeRef: fallthrough
        case .boundGenericClass: fallthrough
        case .boundGenericEnum: fallthrough
        case .boundGenericFunction: fallthrough
        case .boundGenericOtherNominalType: fallthrough
        case .boundGenericProtocol: fallthrough
        case .boundGenericStructure: fallthrough
        case .boundGenericTypeAlias: fallthrough
        case .builtinTypeName: fallthrough
        case .builtinTupleType: fallthrough
        case .builtinFixedArray: fallthrough
        case .class: fallthrough
        case .dependentGenericType: fallthrough
        case .dependentMemberType: fallthrough
        case .dependentGenericParamType: fallthrough
        case .dynamicSelf: fallthrough
        case .enum: fallthrough
        case .errorType: fallthrough
        case .existentialMetatype: fallthrough
        case .integer: fallthrough
        case .labelList: fallthrough
        case .metatype: fallthrough
        case .metatypeRepresentation: fallthrough
        case .module: fallthrough
        case .negativeInteger: fallthrough
        case .otherNominalType: fallthrough
        case .pack: fallthrough
        case .protocol: fallthrough
        case .protocolSymbolicReference: fallthrough
        case .returnType: fallthrough
        case .silBoxType: fallthrough
        case .silBoxTypeWithLayout: fallthrough
        case .structure: fallthrough
        case .sugaredArray: fallthrough
        case .sugaredDictionary: fallthrough
        case .sugaredOptional: fallthrough
        case .sugaredParen: return true
        case .tuple: fallthrough
        case .tupleElementName: fallthrough
        case .typeAlias: fallthrough
        case .typeList: fallthrough
        case .typeSymbolicReference: fallthrough
        case .type:
            return children.first.map { $0.isSimpleType } ?? false
        case .protocolList:
            return children.first.map { $0.children.count <= 1 } ?? false
        case .protocolListWithAnyObject:
            return (children.first?.children.first).map { $0.children.count == 0 } ?? false
        default: return false
        }
    }

    public var needSpaceBeforeType: Bool {
        switch kind {
        case .type: return children.first?.needSpaceBeforeType ?? false
        case .functionType,
             .noEscapeFunctionType,
             .uncurriedFunctionType,
             .dependentGenericType: return false
        default: return true
        }
    }

    public func isIdentifier(desired: String) -> Bool {
        return kind == .identifier && text == desired
    }

    public var isSwiftModule: Bool {
        return kind == .module && text == stdlibName
    }
}


