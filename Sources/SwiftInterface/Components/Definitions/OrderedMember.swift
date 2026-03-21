import MachOSwiftSection

public enum OrderedMember: Sendable {
    case allocator(FunctionDefinition)
    case variable(VariableDefinition)
    case function(FunctionDefinition)
    case `subscript`(SubscriptDefinition)

    /// The minimum vtable slot offset among all descriptors of this member.
    public var minVTableOffset: Int? {
        switch self {
        case .allocator(let f), .function(let f):
            return f.vtableOffset
        case .variable(let v):
            return v.accessors.compactMap(\.vtableOffset).min()
        case .subscript(let s):
            return s.accessors.compactMap(\.vtableOffset).min()
        }
    }

    /// The minimum symbol file offset (MachO offset) among all symbols of this member.
    public var minSymbolOffset: Int {
        switch self {
        case .allocator(let f), .function(let f):
            return f.symbol.offset
        case .variable(let v):
            return v.accessors.map(\.symbol.offset).min() ?? .max
        case .subscript(let s):
            return s.accessors.map(\.symbol.offset).min() ?? .max
        }
    }

    /// The PWT (Protocol Witness Table) offset of this member, used for protocol requirement ordering.
    public var pwtOffset: Int? {
        switch self {
        case .allocator(let f), .function(let f):
            return f.offset
        case .variable(let v):
            return v.offset
        case .subscript(let s):
            return s.offset
        }
    }

    /// Sort: vtable members first (by vtable offset), then remaining (by symbol offset).
    static func classOrdered(_ members: [OrderedMember]) -> [OrderedMember] {
        let withVTable = members.filter { $0.minVTableOffset != nil }
            .sorted { ($0.minVTableOffset ?? 0) < ($1.minVTableOffset ?? 0) }
        let withoutVTable = members.filter { $0.minVTableOffset == nil }
            .sorted { $0.minSymbolOffset < $1.minSymbolOffset }
        return withVTable + withoutVTable
    }

    /// Sort by MachO symbol file offset.
    static func offsetOrdered(_ members: [OrderedMember]) -> [OrderedMember] {
        members.sorted { $0.minSymbolOffset < $1.minSymbolOffset }
    }

    /// Sort by PWT offset (protocol witness table byte offset).
    static func pwtOrdered(_ members: [OrderedMember]) -> [OrderedMember] {
        members.sorted { ($0.pwtOffset ?? .max) < ($1.pwtOffset ?? .max) }
    }

    /// Collect all members from a Definition into a flat list.
    static func allMembers(from definition: some Definition) -> [OrderedMember] {
        var result: [OrderedMember] = []
        result.append(contentsOf: definition.allocators.map { .allocator($0) })
        result.append(contentsOf: definition.variables.map { .variable($0) })
        result.append(contentsOf: definition.functions.map { .function($0) })
        result.append(contentsOf: definition.subscripts.map { .subscript($0) })
        result.append(contentsOf: definition.staticVariables.map { .variable($0) })
        result.append(contentsOf: definition.staticFunctions.map { .function($0) })
        result.append(contentsOf: definition.staticSubscripts.map { .subscript($0) })
        return result
    }
}
