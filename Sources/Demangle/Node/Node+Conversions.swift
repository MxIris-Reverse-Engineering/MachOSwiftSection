extension Node {
    public var text: String? {
        switch contents {
        case .text(let s): return s
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

    public func isIdentifier(desired: String) -> Bool {
        return kind == .identifier && text == desired
    }

    public var isSwiftModule: Bool {
        return kind == .module && text == stdlibName
    }
}

extension Node {
    package func findGenericParamsDepth() -> [UInt64: UInt64]? {
        guard kind == .dependentGenericType, first(of: .dependentGenericParamCount) != nil else { return nil }

        var depths: [UInt64: UInt64] = [:]

        for child in self {
            guard child.kind == .dependentGenericParamType else { continue }
            guard let depth = child.children.at(0)?.index else { continue }
            guard let index = child.children.at(1)?.index else { continue }

            if let currentDepth = depths[index] {
                depths[index] = Swift.max(currentDepth, depth)
            } else {
                depths[index] = depth
            }
        }

        return depths
    }
}
