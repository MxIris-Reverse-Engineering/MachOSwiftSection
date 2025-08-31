import Demangle

enum DefinitionBuilder {
    static func variables(for nodes: [Node], fieldNames: borrowing Set<String>, isStatic: Bool) -> [VariableDefinition] {
        typealias NodeAndVariableKinds = (node: Node, kind: VariableKind)
        var variables: [VariableDefinition] = []
        var nodeAndVariableKindsByName: [String: [NodeAndVariableKinds]] = [:]
        for node in nodes {
            guard let variableNode = node.first(of: .variable) else { continue }
            guard let name = variableNode.identifier else { continue }
            guard let variableKind = node.variableKind else { continue }
            nodeAndVariableKindsByName[name, default: []].append((node, variableKind))
        }

        for (name, nodeAndVariableKinds) in nodeAndVariableKindsByName {
            guard !fieldNames.contains(name) else { continue }
            let nodes = nodeAndVariableKinds.map(\.node)
            guard let node = nodes.first(where: { $0.contains(.getter) }) else { continue }
            let kinds = nodeAndVariableKinds.map(\.kind)
            variables.append(.init(node: node, name: name, hasSetter: kinds.contains(.setter), hasModifyAccessor: kinds.contains(.modifyAccessor), isStatic: isStatic))
        }
        return variables
    }

    static func allocators(for nodes: [Node]) -> [FunctionDefinition] {
        var allocators: [FunctionDefinition] = []
        for node in nodes {
            allocators.append(.init(node: node, name: "", kind: .allocator, isStatic: true))
        }
        return allocators
    }

    static func functions(for nodes: [Node], isStatic: Bool) -> [FunctionDefinition] {
        var functions: [FunctionDefinition] = []
        for node in nodes {
            guard let functionNode = node.first(of: .function), let name = functionNode.identifier else { continue }
            functions.append(.init(node: node, name: name, kind: .function, isStatic: isStatic))
        }
        return functions
    }
}
