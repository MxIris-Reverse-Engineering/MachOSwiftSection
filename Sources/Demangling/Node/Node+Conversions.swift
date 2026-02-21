extension Node {
    @inlinable
    public var text: String? {
        switch payload {
        case .text(let s): return s
        case .oneChild, .twoChildren, .manyChildren:
            // For dependentGenericParamType nodes, derive the name from children (depth, index)
            if kind == .dependentGenericParamType {
                return _genericParamNameFromChildren
            }
            return nil
        default: return nil
        }
    }

    /// Derives the generic parameter name (e.g. "A", "B", "A1") from children.
    /// Children are [Index(depth), Index(index)].
    @usableFromInline
    var _genericParamNameFromChildren: String? {
        guard let depth = firstChild?.index, let idx = children.at(1)?.index else { return nil }
        return genericParameterName(depth: depth, index: idx)
    }

    @inlinable
    public var hasText: Bool {
        switch payload {
        case .text: return true
        case .oneChild, .twoChildren, .manyChildren:
            return kind == .dependentGenericParamType
        default: return false
        }
    }

    public var indexAsCharacter: Character? {
        if let index, let scalar = UnicodeScalar(UInt32(index)) {
            return Character(scalar)
        } else {
            return nil
        }
    }

    @inlinable
    public var index: UInt64? {
        switch payload {
        case .index(let i): return i
        default: return nil
        }
    }

    @inlinable
    public var hasIndex: Bool {
        switch payload {
        case .index: return true
        default: return false
        }
    }

    @inlinable
    public var isNoneContents: Bool {
        switch payload {
        case .none, .oneChild, .twoChildren, .manyChildren: return true
        default: return false
        }
    }

    @inlinable
    public var numberOfChildren: Int {
        switch payload {
        case .none, .index, .text: return 0
        case .oneChild: return 1
        case .twoChildren: return 2
        case .manyChildren(let arr): return arr.count
        }
    }

    @inlinable
    public var hasChildren: Bool {
        switch payload {
        case .none, .index, .text: return false
        default: return true
        }
    }

    @inlinable
    public var firstChild: Node? {
        switch payload {
        case .oneChild(let n): return n
        case .twoChildren(let n, _): return n
        case .manyChildren(let arr): return arr.first
        default: return nil
        }
    }

    @inlinable
    public var lastChild: Node? {
        switch payload {
        case .oneChild(let n): return n
        case .twoChildren(_, let n): return n
        case .manyChildren(let arr): return arr.last
        default: return nil
        }
    }
}

extension Node {
    public var isProtocol: Bool {
        switch kind {
        case .type: return children.first?.isProtocol ?? false
        case .protocol,
             .protocolSymbolicReference,
             .objectiveCProtocolSymbolicReference: return true
        default: return false
        }
    }

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
        case .sugaredInlineArray: fallthrough
        case .sugaredParen: return true
        case .tuple: fallthrough
        case .tupleElementName: fallthrough
        case .typeAlias: fallthrough
        case .typeList: fallthrough
        case .typeSymbolicReference: return true
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

    @inlinable
    public func isIdentifier(desired: String) -> Bool {
        return kind == .identifier && text == desired
    }

    @inlinable
    public var isSwiftModule: Bool {
        return kind == .module && text == stdlibName
    }
}

extension Node {
    @inlinable
    public func isKind(of kinds: Node.Kind...) -> Bool {
        return kinds.contains(kind)
    }
}

extension Node {
    @inlinable
    public subscript(child childIndex: Int) -> Node {
        children[childIndex]
    }

    @inlinable
    public subscript(safeChild childIndex: Int) -> Node? {
        children.at(childIndex)
    }

    @inlinable
    public subscript(throwChild childIndex: Int) -> Node {
        get throws(IndexOutOfBoundError) {
            if let child = children.at(childIndex) {
                return child
            } else {
                throw .default
            }
        }
    }

    public struct IndexOutOfBoundError: Error {
        public static let `default` = IndexOutOfBoundError()
    }
}
