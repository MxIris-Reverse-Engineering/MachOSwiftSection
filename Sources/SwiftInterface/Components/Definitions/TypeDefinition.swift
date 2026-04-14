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
            // Cache for parent class vtable info: parentDescriptorOffset -> (vtableBaseOffset, [methodDescriptorOffset])
            var parentVTableCache: [Int: (baseOffset: Int, methodOffsets: [Int])] = [:]

            for descriptor in cls.methodOverrideDescriptors {
                guard let symbols = try descriptor.implementationSymbols(in: machO) else { continue }
                guard let overrideSymbol = try classDemangledSymbol(for: symbols, typeNode: typeNode, visitedNodes: visitedNodes, in: machO) else { continue }
                let node = overrideSymbol.demangledNode
                visitedNodes.append(node)
                methodDescriptorLookup[node] = .methodOverride(descriptor)

                // Resolve vtable offset for override by looking up the original method in the parent class
                if let vtableSlot = try? resolveOverrideVTableOffset(for: descriptor, cache: &parentVTableCache, in: machO) {
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

        // Build ordered members list
        let allMembers = OrderedMember.allMembers(from: self)
        if case .class = type {
            orderedMembers = OrderedMember.classOrdered(allMembers)
        } else {
            orderedMembers = OrderedMember.offsetOrdered(allMembers)
        }

        isIndexed = true
    }

    /// Resolves the vtable slot offset for an override method descriptor by looking up
    /// the original method in the parent class's vtable.
    private func resolveOverrideVTableOffset<MachO: MachOSwiftSectionRepresentableWithCache>(
        for descriptor: MethodOverrideDescriptor,
        cache: inout [Int: (baseOffset: Int, methodOffsets: [Int])],
        in machO: MachO
    ) throws -> Int? {
        // Resolve the original method descriptor
        guard let methodResult = try descriptor.methodDescriptor(in: machO),
              case .element(let originalMethod) = methodResult else {
            return nil
        }

        // Resolve the parent class descriptor
        guard let classResult = try descriptor.classDescriptor(in: machO),
              case .element(let parentContext) = classResult,
              case .type(.class(let parentClassDescriptor)) = parentContext else {
            return nil
        }

        let parentOffset = parentClassDescriptor.offset

        // Check cache first
        if cache[parentOffset] == nil {
            let parentClass = try Class(descriptor: parentClassDescriptor, in: machO)
            if let header = parentClass.vTableDescriptorHeader {
                let baseOffset = Int(header.layout.vTableOffset)
                let methodOffsets = parentClass.methodDescriptors.map(\.offset)
                cache[parentOffset] = (baseOffset, methodOffsets)
            }
        }

        guard let cached = cache[parentOffset],
              let index = cached.methodOffsets.firstIndex(of: originalMethod.offset) else {
            return nil
        }

        return cached.baseOffset + index
    }

    /// If the given node is an `.extension` wrapper, return the extended type node
    /// (the second child, per Swift demangler's extension node layout:
    /// `extension(module, extendedType, ?genericSignature)`).
    /// Otherwise, return the node as-is. Used when comparing a thunk symbol's
    /// context against a `TypeDefinition`'s type, so members declared in extensions
    /// match the same way as members declared directly on the type.
    private static func unwrapExtensionContext(_ node: Node) -> Node {
        if node.kind == .extension, let extendedType = node.children.at(1) {
            return extendedType
        }
        return node
    }

    /// Cross-references @objc and @nonobjc thunk symbols with already-built member definitions,
    /// appending the appropriate attribute to matching members.
    ///
    /// Thunk symbol node structures:
    /// - `global(objCAttribute, function(context, identifier(name), ...))`
    /// - `global(objCAttribute, static(function(context, identifier(name), ...)))`
    /// - `global(nonObjCAttribute, getter(variable(context, identifier(name))))`
    private func applyThunkAttributes<MachO: MachORepresentableWithCache>(
        symbolIndexStore: SymbolIndexStore,
        typeName: String,
        in machO: MachO
    ) {
        let thunkKindsAndAttributes: [(Node.Kind, SwiftAttribute)] = [
            (.objCAttribute, .objc),
            (.nonObjCAttribute, .nonobjc),
        ]

        for (thunkKind, attribute) in thunkKindsAndAttributes {
            let thunkSymbols = symbolIndexStore.symbols(of: thunkKind, in: machO)
            for thunkSymbol in thunkSymbols {
                let rootNode = thunkSymbol.demangledNode

                // Find the member node: the child of .global that is NOT the attribute marker
                guard let memberNode = rootNode.children.first(where: { $0.kind != thunkKind }) else { continue }

                // Unwrap .static if present and track whether this is a static member
                let isStatic: Bool
                let unwrappedMemberNode: Node
                if memberNode.kind == .static, let innerChild = memberNode.children.first {
                    isStatic = true
                    unwrappedMemberNode = innerChild
                } else {
                    isStatic = false
                    unwrappedMemberNode = memberNode
                }

                // Extract context and member name based on the member node kind.
                // For members declared in an extension, the context is wrapped in a
                // `.extension` node whose second child is the extended type. We unwrap
                // it here so the type-matching below sees the raw type node, regardless
                // of whether the thunk originated from a direct declaration or an
                // extension.
                let extractedMemberName: String?
                let contextNode: Node?

                switch unwrappedMemberNode.kind {
                case .function, .constructor, .allocator:
                    contextNode = unwrappedMemberNode.children.first.map(Self.unwrapExtensionContext)
                    extractedMemberName = unwrappedMemberNode.identifier
                case .variable:
                    contextNode = unwrappedMemberNode.children.first.map(Self.unwrapExtensionContext)
                    extractedMemberName = unwrappedMemberNode.identifier
                case .getter, .setter:
                    // Accessor wrapping a variable: getter(variable(context, identifier(name)))
                    if let innerVariable = unwrappedMemberNode.children.first, innerVariable.kind == .variable {
                        contextNode = innerVariable.children.first.map(Self.unwrapExtensionContext)
                        extractedMemberName = innerVariable.identifier
                    } else if let innerSubscript = unwrappedMemberNode.children.first, innerSubscript.kind == .subscript {
                        contextNode = innerSubscript.children.first.map(Self.unwrapExtensionContext)
                        extractedMemberName = nil // Subscripts don't have a simple name to match
                    } else {
                        contextNode = nil
                        extractedMemberName = nil
                    }
                default:
                    contextNode = nil
                    extractedMemberName = nil
                }

                guard let contextNode else { continue }

                // Check if the context matches the current type by comparing printed names
                let thunkTypeName = Node.create(kind: .type, child: contextNode).print(using: .interfaceTypeBuilderOnly)
                guard thunkTypeName == typeName else { continue }

                guard let extractedMemberName else { continue }

                // Match against the appropriate definition arrays based on static/instance
                if isStatic {
                    applyAttributeToFunction(name: extractedMemberName, attribute: attribute, in: &staticFunctions)
                    applyAttributeToVariable(name: extractedMemberName, attribute: attribute, in: &staticVariables)
                } else {
                    applyAttributeToFunction(name: extractedMemberName, attribute: attribute, in: &functions)
                    applyAttributeToVariable(name: extractedMemberName, attribute: attribute, in: &variables)
                    // Also check allocators (for @objc init thunks)
                    if unwrappedMemberNode.kind == .allocator || unwrappedMemberNode.kind == .constructor {
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
}
