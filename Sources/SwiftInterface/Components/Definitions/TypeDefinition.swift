import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangling
import Semantic
import SwiftStdlibToolbox
import Dependencies
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

public final class TypeDefinition: Definition {
    public enum ParentContext {
        case `extension`(ExtensionContext)
        case type(TypeContextWrapper)
        case symbol(Symbol)
    }

    public let type: TypeContextWrapper

    public let typeName: TypeName

    public internal(set) weak var parent: TypeDefinition?

    public internal(set) var typeChildren: [TypeDefinition] = []

    public internal(set) var protocolChildren: [ProtocolDefinition] = []

    public internal(set) var parentContext: ParentContext? = nil

    public internal(set) var extensions: [ExtensionDefinition] = []

    public internal(set) var fields: [FieldDefinition] = []

    public internal(set) var variables: [VariableDefinition] = []

    public internal(set) var functions: [FunctionDefinition] = []

    public internal(set) var subscripts: [SubscriptDefinition] = []

    public internal(set) var staticVariables: [VariableDefinition] = []

    public internal(set) var staticFunctions: [FunctionDefinition] = []

    public internal(set) var staticSubscripts: [SubscriptDefinition] = []

    public internal(set) var allocators: [FunctionDefinition] = []

    public internal(set) var constructors: [FunctionDefinition] = []

    /// The deallocator symbol (`fD`) that backs the dump's `deinit` line.
    ///
    /// - On classes, this is `__deallocating_deinit`: the ARC tear-down
    ///   thunk that calls the user's `deinit` body and frees the storage.
    /// - On `~Copyable` structs/enums, this is the user's `deinit` body
    ///   itself (value types have no separate destructor slot, so the
    ///   compiler reuses the deallocator slot for the user code; the
    ///   demangler prints it as plain `deinit`).
    /// - Regular (copyable) structs/enums have no deallocator, so this is
    ///   nil and `deinit` is suppressed in the dump.
    public internal(set) var deallocatorSymbol: DemangledSymbol? = nil

    /// The destructor symbol (`fd`) on classes — the actual Swift `deinit`
    /// body the user wrote (or a shared empty implementation when there is
    /// none). It is reached at runtime via the deallocator above.
    ///
    /// Only emitted for classes; absent for actors and value types, so
    /// look-ups return nil for those. We do not use this symbol to decide
    /// whether to print the `deinit` keyword — the deallocator is a more
    /// uniform anchor — but its address is exposed alongside the
    /// deallocator address so reverse engineers can jump directly to the
    /// user code.
    public internal(set) var destructorSymbol: DemangledSymbol? = nil

    public var hasDeallocator: Bool { deallocatorSymbol != nil }

    public internal(set) var orderedMembers: [OrderedMember] = []

    public internal(set) var conformingProtocolNames: Set<String> = []

    public internal(set) var attributes: [SwiftAttribute] = []

    public private(set) var isIndexed: Bool = false

    public var hasMembers: Bool {
        !fields.isEmpty || !variables.isEmpty || !functions.isEmpty ||
            !subscripts.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !staticSubscripts.isEmpty || !allocators.isEmpty || !constructors.isEmpty || hasDeallocator
    }

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(type: TypeContextWrapper, in machO: MachO) async throws {
        self.type = type
        let typeName = try type.typeName(in: machO)
        self.typeName = typeName
    }

    package func index<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) async throws {
        guard !isIndexed else { return }

        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        var fields: [FieldDefinition] = []
        let typeContextDescriptor = try required(type.contextDescriptorWrapper.typeContextDescriptor)
        let fieldDescriptor = try typeContextDescriptor.fieldDescriptor(in: machO)
        let records = try fieldDescriptor.records(in: machO)
        for record in records {
            let typeNode = try record.demangledTypeNode(in: machO)
            let name = try record.fieldName(in: machO)
            var fieldFlags = FieldFlags()
            if name.hasLazyPrefix {
                fieldFlags.insert(.isLazy)
            }
            if typeNode.contains(.weak) {
                fieldFlags.insert(.isWeak)
            }
            if typeNode.contains(.unmanaged) {
                fieldFlags.insert(.isUnownedUnsafe)
            } else if typeNode.contains(.unowned) {
                fieldFlags.insert(.isUnowned)
            }
            if record.flags.contains(.isVariadic) {
                fieldFlags.insert(.isVariable)
            }
            if record.flags.contains(.isIndirectCase) {
                fieldFlags.insert(.isIndirectCase)
            }
            if record.flags.contains(.isArtificial) {
                fieldFlags.insert(.isArtificial)
            }
            let field = FieldDefinition(name: name.stripLazyPrefix, typeNode: typeNode, flags: fieldFlags)
            fields.append(field)
        }

        self.fields = fields

        let fieldNames = Set(fields.map(\.name))

        var methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:]
        var vtableOffsetLookup: [Node: Int] = [:]
        // Fallback lookups keyed by implementation file offset (for methods where node-based matching fails)
        var implOffsetDescriptorLookup: [Int: MethodDescriptorWrapper] = [:]
        var implOffsetVTableSlotLookup: [Int: Int] = [:]
        if case .class(let cls) = type {
            var visitedNodes: OrderedSet<Node> = []
            let typeNode = try MetadataReader.demangleContext(for: .type(.class(cls.descriptor)), in: machO)
            let vtableBaseOffset = cls.vTableDescriptorHeader.map { Int($0.layout.vTableOffset) }

            // Build offset-based fallback lookups. Uniqueness must be checked against
            // ALL descriptor kinds (method + override + defaultOverride), because
            // trampolines/thunks/shared implementations can have multiple descriptors
            // pointing at the same impl address. If the impl is not globally unique,
            // we cannot use offset-based fallback — we would not know which descriptor
            // to associate the symbol with.
            var implOffsetCounts: [Int: Int] = [:]
            for descriptor in cls.methodDescriptors where !descriptor.implementation.isNull {
                let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                implOffsetCounts[implOffset, default: 0] += 1
            }
            for descriptor in cls.methodOverrideDescriptors where !descriptor.implementation.isNull {
                let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                implOffsetCounts[implOffset, default: 0] += 1
            }
            for descriptor in cls.methodDefaultOverrideDescriptors where !descriptor.implementation.isNull {
                let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                implOffsetCounts[implOffset, default: 0] += 1
            }
            for (index, descriptor) in cls.methodDescriptors.enumerated() where !descriptor.implementation.isNull {
                let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                // Only use offset-based fallback for globally unique implementation addresses
                if implOffsetCounts[implOffset] == 1 {
                    implOffsetDescriptorLookup[implOffset] = .method(descriptor)
                    if let vtableBaseOffset {
                        implOffsetVTableSlotLookup[implOffset] = vtableBaseOffset + index
                    }
                }
            }

            for (index, descriptor) in cls.methodDescriptors.enumerated() {
                guard let symbols = try descriptor.implementationSymbols(in: machO) else { continue }
                guard let overrideSymbol = try classDemangledSymbol(for: symbols, typeNode: typeNode, visitedNodes: visitedNodes, in: machO) else { continue }
                let node = overrideSymbol.demangledNode
                visitedNodes.append(node)
                methodDescriptorLookup[node] = .method(descriptor)
                if let vtableBaseOffset {
                    vtableOffsetLookup[node] = vtableBaseOffset + index
                }
            }
            var parentVTableCache = ParentClassVTableCache()

            for descriptor in cls.methodOverrideDescriptors {
                guard let symbols = try descriptor.implementationSymbols(in: machO) else { continue }
                guard let overrideSymbol = try classDemangledSymbol(for: symbols, typeNode: typeNode, visitedNodes: visitedNodes, in: machO) else { continue }
                let node = overrideSymbol.demangledNode
                visitedNodes.append(node)
                methodDescriptorLookup[node] = .methodOverride(descriptor)

                if let vtableSlot = try? parentVTableCache.slotIndex(for: descriptor, in: machO) {
                    vtableOffsetLookup[node] = vtableSlot
                }
            }
            for descriptor in cls.methodDefaultOverrideDescriptors {
                guard let symbols = try descriptor.implementationSymbols(in: machO) else { continue }
                guard let overrideSymbol = try classDemangledSymbol(for: symbols, typeNode: typeNode, visitedNodes: visitedNodes, in: machO) else { continue }
                let node = overrideSymbol.demangledNode
                visitedNodes.append(node)
                methodDescriptorLookup[node] = .methodDefaultOverride(descriptor)
            }
        }

        let name = typeName.name
        let node = typeName.node

        allocators = DefinitionBuilder.allocators(
            for: symbolIndexStore.memberSymbols(of: .allocator(inExtension: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup
        )

        // See the property doc comments for the role each symbol plays.
        // The deallocator drives whether `deinit` is printed at all; the
        // destructor (only present on classes) is exposed as an extra
        // address comment.
        deallocatorSymbol = symbolIndexStore.memberSymbols(of: .deallocator, for: typeName.name, in: machO).first
        destructorSymbol = symbolIndexStore.memberSymbols(of: .destructor, for: typeName.name, in: machO).first

        variables = DefinitionBuilder.variables(
            for: symbolIndexStore.memberSymbols(of: .variable(inExtension: false, isStatic: false, isStorage: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            fieldNames: fieldNames,
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isGlobalOrStatic: false
        )

        staticVariables = DefinitionBuilder.variables(
            for: symbolIndexStore.memberSymbols(
                of: .variable(inExtension: false, isStatic: true, isStorage: false),
                .variable(inExtension: false, isStatic: true, isStorage: true),
                for: name,
                node: node,
                in: machO
            ).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isGlobalOrStatic: true
        )

        functions = DefinitionBuilder.functions(
            for: symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isGlobalOrStatic: false
        )

        staticFunctions = DefinitionBuilder.functions(
            for: symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: true), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isGlobalOrStatic: true
        )

        subscripts = DefinitionBuilder.subscripts(
            for: symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isStatic: false
        )

        staticSubscripts = DefinitionBuilder.subscripts(
            for: symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: true), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isStatic: true
        )

        // Cross-reference @objc and @nonobjc thunk symbols with built definitions
        applyThunkAttributes(symbolIndexStore: symbolIndexStore, typeName: name, in: machO)

        // P1-10: drop body-side copies of auto-synthesized Equatable / Hashable /
        // Codable / CaseIterable / RawRepresentable / CodingKey members. The
        // canonical copy remains on the conformance extension, avoiding the
        // "same member printed twice with different addresses" duplication.
        // This must run *after* applyThunkAttributes so that any user-declared
        // override flagged with an attribute is dropped alongside its body
        // entry; the extension copy (which carries the same attribute after
        // its own indexing pass) is the surviving one.
        deduplicateSynthesizedProtocolMembers()

        // Build ordered members list
        let allMembers = OrderedMember.allMembers(from: self)
        if case .class = type {
            orderedMembers = OrderedMember.classOrdered(allMembers)
        } else {
            orderedMembers = OrderedMember.offsetOrdered(allMembers)
        }

        isIndexed = true
    }

    /// Cross-references `@objc` / `@nonobjc` thunk attribute members (pre-extracted
    /// and bucketed by parent type name inside `SymbolIndexStore`) with the
    /// already-built member definitions of this type, appending the matching
    /// attribute to each affected member.
    private func applyThunkAttributes<MachO: MachORepresentableWithCache>(
        symbolIndexStore: SymbolIndexStore,
        typeName: String,
        in machO: MachO
    ) {
        let thunkKindsAndAttributes: [(Node.Kind, SwiftAttribute)] = [
            (.objCAttribute, .objc),
            (.nonObjCAttribute, .nonobjc),
            (.distributedThunk, .distributed),
        ]

        for (thunkKind, attribute) in thunkKindsAndAttributes {
            let members = symbolIndexStore.thunkAttributeMembers(of: thunkKind, for: typeName, in: machO)
            for member in members {
                if member.isStatic {
                    applyAttributeToFunction(name: member.memberName, attribute: attribute, in: &staticFunctions)
                    applyAttributeToVariable(name: member.memberName, attribute: attribute, in: &staticVariables)
                } else {
                    applyAttributeToFunction(name: member.memberName, attribute: attribute, in: &functions)
                    applyAttributeToVariable(name: member.memberName, attribute: attribute, in: &variables)
                    if member.isInit {
                        applyAttributeToAllocator(attribute: attribute, in: &allocators)
                    }
                }
            }
        }
    }

    private func applyAttributeToFunction(name: String, attribute: SwiftAttribute, in definitions: inout [FunctionDefinition]) {
        for definitionIndex in definitions.indices {
            if definitions[definitionIndex].name == name && !definitions[definitionIndex].attributes.contains(attribute) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }

    private func applyAttributeToVariable(name: String, attribute: SwiftAttribute, in definitions: inout [VariableDefinition]) {
        for definitionIndex in definitions.indices {
            if definitions[definitionIndex].name == name && !definitions[definitionIndex].attributes.contains(attribute) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }

    private func applyAttributeToAllocator(attribute: SwiftAttribute, in definitions: inout [FunctionDefinition]) {
        for definitionIndex in definitions.indices {
            if !definitions[definitionIndex].attributes.contains(attribute) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }

    /// Drops body-side copies of members that Swift auto-synthesizes for
    /// `Equatable` / `Hashable` / `Codable` / `CaseIterable` / `RawRepresentable` /
    /// `CodingKey` conformances. These members are emitted twice in binary
    /// metadata — once as a direct entry on the nominal type (which ends up in
    /// this type's `functions` / `staticFunctions` / `variables`) and once as a
    /// witness thunk on the protocol conformance descriptor (which ends up in
    /// the generated conformance extension). The extension copy is the one
    /// Swift source conventionally shows for these protocols, so we drop the
    /// body-side copy.
    ///
    /// Detection is gated on the type actually conforming to the relevant
    /// protocol (via `conformingProtocolNames`), and on the member matching
    /// the canonical synthesized shape (name + label list). A user-written
    /// override with a compatible signature will also be dropped from the
    /// body, but the equivalent entry remains visible in the conformance
    /// extension, so nothing is hidden — the output is just no longer
    /// duplicated. See roadmap P1-10.
    private func deduplicateSynthesizedProtocolMembers() {
        // Precompute the short (unqualified) names of every protocol this
        // type conforms to, so downstream checks can ignore module qualifiers.
        var shortProtocolNames: Set<String> = []
        for protocolName in conformingProtocolNames {
            if let dotIndex = protocolName.lastIndex(of: ".") {
                shortProtocolNames.insert(String(protocolName[protocolName.index(after: dotIndex)...]))
            } else {
                shortProtocolNames.insert(protocolName)
            }
        }

        if shortProtocolNames.isEmpty { return }

        // Returns the argument label list of a member as an array of strings,
        // with "_" for unnamed parameters. Works on function / constructor /
        // allocator / getter nodes; returns an empty array if no labelList
        // node exists (which means the function either takes no parameters
        // or takes exclusively unnamed parameters — the demangler does not
        // always emit an explicit labelList for the all-unnamed case).
        func labels(of node: Node) -> [String] {
            guard let list = node.first(of: .labelList) else { return [] }
            return list.children.map { child in
                if child.kind == .firstElementMarker { return "_" }
                return child.text ?? "_"
            }
        }

        // Hashable implies Equatable, but Swift still emits both conformances,
        // so we check them independently.
        //
        // `==` is the Swift operator name and is uniquely reserved for
        // Equatable-shaped comparison at source level, so matching on name
        // alone is safe. The argument labels of `==` are always unnamed
        // (`_`, `_`) and the demangler elides the labelList in that case,
        // which is why we cannot gate on a `[_, _]` label shape here.
        if shortProtocolNames.contains("Equatable") || shortProtocolNames.contains("Hashable") {
            staticFunctions.removeAll { function in
                function.name == "=="
            }
        }

        if shortProtocolNames.contains("Hashable") {
            functions.removeAll { function in
                (function.name == "hash" && labels(of: function.node) == ["into"])
                    || (function.name == "_rawHashValue" && labels(of: function.node) == ["seed"])
            }
            variables.removeAll { variable in
                variable.name == "hashValue"
            }
        }

        if shortProtocolNames.contains("CaseIterable") {
            staticVariables.removeAll { variable in
                variable.name == "allCases"
            }
        }

        if shortProtocolNames.contains("RawRepresentable") {
            variables.removeAll { variable in
                variable.name == "rawValue"
            }
            // `init?(rawValue:)` can appear either as an allocator or a constructor
            // depending on whether the type has its metadata accessor.
            allocators.removeAll { function in
                labels(of: function.node) == ["rawValue"]
            }
            constructors.removeAll { function in
                labels(of: function.node) == ["rawValue"]
            }
        }

        if shortProtocolNames.contains("Encodable") || shortProtocolNames.contains("Codable") {
            functions.removeAll { function in
                function.name == "encode" && labels(of: function.node) == ["to"]
            }
        }

        if shortProtocolNames.contains("Decodable") || shortProtocolNames.contains("Codable") {
            allocators.removeAll { function in
                labels(of: function.node) == ["from"]
            }
            constructors.removeAll { function in
                labels(of: function.node) == ["from"]
            }
        }

        if shortProtocolNames.contains("CodingKey") {
            variables.removeAll { variable in
                variable.name == "stringValue" || variable.name == "intValue"
            }
            allocators.removeAll { function in
                labels(of: function.node) == ["stringValue"] || labels(of: function.node) == ["intValue"]
            }
            constructors.removeAll { function in
                labels(of: function.node) == ["stringValue"] || labels(of: function.node) == ["intValue"]
            }
        }
    }
}
