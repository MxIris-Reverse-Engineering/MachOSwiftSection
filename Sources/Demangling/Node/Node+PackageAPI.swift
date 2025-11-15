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

    package var identifier: String? {
        if let node = children.at(1), node.kind == .identifier {
            return node.text
        } else if let node = children.at(1), node.kind == .privateDeclName {
            return node.children.at(1)?.text
        } else if let node = first(of: .prefixOperator, .postfixOperator, .infixOperator) {
            return node.text
        } else if let node = first(of: .identifier) {
            return node.text
        } else if let node = first(of: .privateDeclName) {
            return node.children.at(1)?.text
        } else {
            return nil
        }
    }
}
