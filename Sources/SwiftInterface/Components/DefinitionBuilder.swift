import Demangle

enum DefinitionBuilder {
    private typealias NodeAndKinds = (node: Node, kind: AccessorKind?)
    
    static func variables(for nodes: [Node], fieldNames: borrowing Set<String>, isGlobalOrStatic: Bool) -> [VariableDefinition] {
        var variables: [VariableDefinition] = []
        var nodeAndKindsByName: [String: [NodeAndKinds]] = [:]
        for node in nodes {
            guard let variableNode = node.first(of: .variable) else { continue }
            guard let name = variableNode.identifier else { continue }
            let kind = node.accessorKind
            nodeAndKindsByName[name, default: []].append((node, kind))
        }

        for (name, nodeAndVariableKinds) in nodeAndKindsByName {
            guard !fieldNames.contains(name) else { continue }
            let nodes = nodeAndVariableKinds.map(\.node)
            guard let node = nodes.first(where: { $0.contains(.getter) || !$0.hasAccessor }) else { continue }
            let kinds = nodeAndVariableKinds.map(\.kind)
            variables.append(.init(node: node, name: name, hasSetter: kinds.contains(.setter), hasModifyAccessor: kinds.contains(.modifyAccessor), isGlobalOrStatic: isGlobalOrStatic, isStored: kinds.contains(nil)))
        }
        return variables
    }

    static func subscripts(for nodes: [Node], isStatic: Bool) -> [SubscriptDefinition] {
        var subscripts: [SubscriptDefinition] = []
        var nodeAndKindsByName: [Node: [NodeAndKinds]] = [:]
        for node in nodes {
            guard let subscriptNode = node.first(of: .subscript) else { continue }
            guard let kind = node.accessorKind else { continue }
            nodeAndKindsByName[subscriptNode, default: []].append((node, kind))
        }

        for (_, nodeAndVariableKinds) in nodeAndKindsByName {
            let nodes = nodeAndVariableKinds.map(\.node)
            guard let node = nodes.first(where: { $0.contains(.getter) }) else { continue }
            let kinds = nodeAndVariableKinds.map(\.kind)
            subscripts.append(.init(node: node, hasSetter: kinds.contains(.setter), hasReadAccessor: kinds.contains(.readAccessor), hasModifyAccessor: kinds.contains(.modifyAccessor), isStatic: isStatic))
        }
        return subscripts
    }
    
    
    static func allocators(for nodes: [Node]) -> [FunctionDefinition] {
        var allocators: [FunctionDefinition] = []
        for node in nodes {
            allocators.append(.init(node: node, name: "", kind: .allocator, isGlobalOrStatic: true))
        }
        return allocators
    }

    static func functions(for nodes: [Node], isGlobalOrStatic: Bool) -> [FunctionDefinition] {
        var functions: [FunctionDefinition] = []
        for node in nodes {
            guard let functionNode = node.first(of: .function), let name = functionNode.identifier else { continue }
            functions.append(.init(node: node, name: name, kind: .function, isGlobalOrStatic: isGlobalOrStatic))
        }
        return functions
    }
}

extension Node {
    var isStoredVariable: Bool {
        guard let variableNode = first(of: .variable) else { return false }
        return variableNode.parent?.isAccessor == false
    }
}
