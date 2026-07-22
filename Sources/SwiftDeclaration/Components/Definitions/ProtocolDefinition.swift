import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import Demangling
import Semantic
import SwiftStdlibToolbox
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

@MemberwiseInit()
@dynamicMemberLookup
package struct DemangledSymbolWithOffset {
    package let base: DemangledSymbol
    package let offset: Int?

    package init(_ base: DemangledSymbol) {
        self.base = base
        self.offset = nil
    }

    package subscript<Value>(dynamicMember keyPath: KeyPath<DemangledSymbol, Value>) -> Value {
        base[keyPath: keyPath]
    }
}

extension Sequence<DemangledSymbol> {
    package func mapToDemangledSymbolWithOffset() -> [DemangledSymbolWithOffset] {
        map { .init($0) }
    }
}

public struct StrippedSymbolicRequirement: Sendable {
    public let requirement: ProtocolRequirement
    public let pwtOffset: Int
}

extension StrippedSymbolicRequirement {
    /// Mach-O-free facts about the stripped requirement, exposed so consumers
    /// that must not touch Mach-O types (SwiftDiffing keys its ABI records on
    /// these) get a stable facade. `kindToken` is an explicit switch — the
    /// tokens are part of the persisted ABI-key scheme, so renaming one is a
    /// key-scheme change (bump `ABISnapshotDocument.currentFormatVersion`).
    public var kindToken: String {
        switch requirement.layout.flags.kind {
        case .baseProtocol: return "baseProtocol"
        case .method: return "method"
        case .`init`: return "init"
        case .getter: return "getter"
        case .setter: return "setter"
        case .readCoroutine: return "readCoroutine"
        case .modifyCoroutine: return "modifyCoroutine"
        case .associatedTypeAccessFunction: return "associatedTypeAccessFunction"
        case .associatedConformanceAccessFunction: return "associatedConformanceAccessFunction"
        }
    }

    public var isInstance: Bool {
        requirement.layout.flags.isInstance
    }

    public var isAsync: Bool {
        requirement.layout.flags.isAsync
    }

    /// Whether the requirement carries a default implementation (a valid
    /// relative pointer — pure arithmetic, no resolution).
    public var hasDefaultImplementation: Bool {
        requirement.layout.defaultImplementation.isValid
    }
}

public final class ProtocolDefinition: Definition, MutableDefinition {
    public let `protocol`: MachOSwiftSection.`Protocol`

    public let protocolName: ProtocolName

    public package(set) weak var parent: TypeDefinition?

    public package(set) var extensionContext: ExtensionContext? = nil

    public package(set) var defaultImplementationExtensions: [ExtensionDefinition] = []

    public package(set) var associatedTypes: [String] = []

    public package(set) var allocators: [FunctionDefinition] = []

    public package(set) var constructors: [FunctionDefinition] = []

    public package(set) var variables: [VariableDefinition] = []

    public package(set) var functions: [FunctionDefinition] = []

    public package(set) var subscripts: [SubscriptDefinition] = []

    public package(set) var staticVariables: [VariableDefinition] = []

    public package(set) var staticFunctions: [FunctionDefinition] = []

    public package(set) var staticSubscripts: [SubscriptDefinition] = []

    public package(set) var strippedSymbolicRequirements: [StrippedSymbolicRequirement] = []

    public package(set) var orderedMembers: [OrderedMember] = []

    public private(set) var isIndexed: Bool = false

    public var hasMembers: Bool {
        !associatedTypes.isEmpty || !variables.isEmpty || !functions.isEmpty ||
            !subscripts.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !staticSubscripts.isEmpty || !allocators.isEmpty || !constructors.isEmpty || !strippedSymbolicRequirements.isEmpty
    }

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(`protocol`: MachOSwiftSection.`Protocol`, in machO: MachO) throws {
        self.protocol = `protocol`
        let node = try MetadataReader.demangleContext(for: .protocol(`protocol`.descriptor), in: machO)
        self.protocolName = ProtocolName(node: node)
    }

    package func index<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) async throws {
        guard !isIndexed else { return }
        let name = protocolName.name
        func _symbol(for symbols: Symbols, visitedNodes: borrowing OrderedSet<Node> = []) throws -> DemangledSymbol? {
            for symbol in symbols {
                if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolNode = node.first(of: .protocol), protocolNode.print(using: .interfaceTypeBuilderOnly) == name, !visitedNodes.contains(node) {
                    return .init(symbol: symbol, demangledNode: node)
                }
            }
            return nil
        }
        associatedTypes = try `protocol`.descriptor.associatedTypes(in: machO)

        var requirementMemberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbolWithOffset]> = [:]
        var defaultImplementationMemberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbolWithOffset]> = [:]

        var requirementVisitedNodes: OrderedSet<Node> = []
        var defaultImplementationVisitedNodes: OrderedSet<Node> = []

        var offsetOfPWT = 0

        for requirement in `protocol`.requirements {
            offsetOfPWT.offset(of: StoredPointer.self)
            guard let symbols = try await Symbols.resolve(from: requirement.offset, in: machO), let symbol = try? _symbol(for: symbols, visitedNodes: requirementVisitedNodes) else {
                strippedSymbolicRequirements.append(.init(requirement: requirement, pwtOffset: offsetOfPWT))
                continue
            }
            requirementVisitedNodes.append(symbol.demangledNode)
            addSymbol(.init(base: symbol, offset: offsetOfPWT), memberSymbolsByKind: &requirementMemberSymbolsByKind, inExtension: false)
            if let symbols = try requirement.defaultImplementationSymbols(in: machO), let defaultImplementationSymbol = try _symbol(for: symbols, visitedNodes: defaultImplementationVisitedNodes) {
                defaultImplementationVisitedNodes.append(defaultImplementationSymbol.demangledNode)
                addSymbol(.init(base: defaultImplementationSymbol, offset: offsetOfPWT), memberSymbolsByKind: &defaultImplementationMemberSymbolsByKind, inExtension: true)
            }
        }

        setDefinitions(for: requirementMemberSymbolsByKind, inExtension: false)

        orderedMembers = OrderedMember.pwtOrdered(OrderedMember.allMembers(from: self))

        let extensionDefinition = try ExtensionDefinition(extensionName: protocolName.extensionName, genericSignature: nil, protocolConformance: nil, in: machO)

        extensionDefinition.setDefinitions(for: defaultImplementationMemberSymbolsByKind, inExtension: true)
        extensionDefinition.orderedMembers = OrderedMember.offsetOrdered(OrderedMember.allMembers(from: extensionDefinition))

        if extensionDefinition.hasMembers {
            defaultImplementationExtensions = [extensionDefinition]
        }

        isIndexed = true
    }
}
