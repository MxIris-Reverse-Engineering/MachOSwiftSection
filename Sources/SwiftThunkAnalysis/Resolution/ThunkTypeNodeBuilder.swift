import Foundation
import FoundationToolbox
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection

@Loggable(.fileprivate, subsystem: "com.machoswiftsection.swift-thunk-analysis", category: "ThunkTypeNodeBuilder")
fileprivate protocol ThunkTypeNodeBuildingLogging {}

/// Turns what the evaluator computed into a demangling tree.
///
/// Three leaves and one node. A constant metadata address names itself
/// (its exported `…VN` symbol, or the record's descriptor). An argument
/// names the thunk owner's generic parameter at that position — the layout
/// the caller supplies says which depth and index the position is — as the
/// same `dependentGenericParamType` node a demangled field type carries, so
/// the existing substitution rewrites it into the concrete argument. A
/// mangled name is demangled. And an accessor applied to arguments becomes
/// the accessor's nominal type with a `boundGeneric*` wrapper per generic
/// level of its declaration chain, the way the demangler itself spells
/// `Outer<Int>.Inner<String>`.
package struct ThunkTypeNodeBuilder: ThunkTypeNodeBuildingLogging {
    package let machO: MachOFile
    package let environment: MachOThunkEnvironment
    package let ownerLayout: AccessorThunkOwnerLayout

    package init(machO: MachOFile, environment: MachOThunkEnvironment, ownerLayout: AccessorThunkOwnerLayout) {
        self.machO = machO
        self.environment = environment
        self.ownerLayout = ownerLayout
    }

    /// A `.type`-enveloped node for `expression`, or `nil` when some part of
    /// it cannot be named.
    package func typeNode(for expression: ThunkTypeExpression) -> Node? {
        switch expression {
        case .argument(let index):
            guard let position = ownerLayout.genericParameterPosition(ofKeyArgumentAt: index) else {
                #log(.info, "argument \(index, privacy: .public) is not one of the owner's generic parameters")
                return nil
            }
            let parameterNode = Node.create(kind: .dependentGenericParamType, children: [
                Node.create(kind: .index, index: UInt64(position.depth)),
                Node.create(kind: .index, index: UInt64(position.index)),
            ])
            return Node.create(kind: .type, children: [parameterNode])
        case .constantMetadata(let address):
            return MetadataNaming.typeNode(forMetadataAt: address, addressSpace: environment.addressSpace, in: machO).map(enveloped)
        case .bound(let accessorAddress, let typeArguments):
            return boundTypeNode(accessorAddress: accessorAddress, typeArguments: typeArguments)
        case .instantiatedFromMangledName(let argumentAddresses):
            // The V2 helper takes `(cache, mangledNameReference)`; the older
            // one keeps the reference inside the cache variable. Try the last
            // argument first so the cache word is never misread as a
            // reference when a real one was passed.
            for address in argumentAddresses.reversed() {
                if let node = typeNode(forMangledNamePointerAt: address) { return enveloped(node) }
            }
            return nil
        }
    }

    // MARK: - Bound generics

    private static let nominalKinds: Set<Node.Kind> = [.structure, .enum, .class, .otherNominalType, .typeAlias]

    private static func boundKind(for kind: Node.Kind) -> Node.Kind? {
        switch kind {
        case .structure: .boundGenericStructure
        case .enum: .boundGenericEnum
        case .class: .boundGenericClass
        case .otherNominalType: .boundGenericOtherNominalType
        case .typeAlias: .boundGenericTypeAlias
        default: nil
        }
    }

    private func boundTypeNode(accessorAddress: UInt64, typeArguments: [ThunkTypeExpression]) -> Node? {
        guard let origin = environment.accessorOriginsByAddress[accessorAddress] else { return nil }
        do {
            let descriptor: ContextDescriptorWrapper = try ContextDescriptorWrapper.resolve(from: origin.descriptorOffset, in: origin.machO)
            let unboundNode = try SymbolicDemangler.demangleContext(for: descriptor, in: origin.machO)
            guard let keyParameterCountsByLevel = try keyParameterCountsByNominalLevel(of: descriptor, in: origin.machO) else { return nil }
            var argumentNodes: [Node] = []
            for typeArgument in typeArguments {
                guard let argumentNode = typeNode(for: typeArgument) else { return nil }
                argumentNodes.append(argumentNode)
            }
            guard keyParameterCountsByLevel.reduce(0, +) == argumentNodes.count else {
                #log(.info, "accessor at 0x\(String(accessorAddress, radix: 16), privacy: .public) takes \(keyParameterCountsByLevel.reduce(0, +), privacy: .public) type arguments, \(argumentNodes.count, privacy: .public) were named")
                return nil
            }
            let nominalNode = unboundNode.kind == .type ? unboundNode.firstChild : unboundNode
            guard let nominalNode,
                  let boundNode = bound(nominalNode, keyParameterCountsByLevel: keyParameterCountsByLevel[...], arguments: argumentNodes[...])
            else { return nil }
            return enveloped(boundNode)
        } catch {
            #log(.info, "could not name the accessor at 0x\(String(accessorAddress, radix: 16), privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// One entry per *type* context on the declaration chain, outermost
    /// first: how many key generic parameters that level itself declares.
    ///
    /// Answers `nil` for a chain some parameter of which takes no key
    /// argument (a same-type-constrained parameter the runtime derives
    /// rather than receives): the accessor's arguments then no longer line
    /// up one-to-one with the parameters a bound node must spell, and
    /// spelling only the received ones would print a real, wrong type.
    private func keyParameterCountsByNominalLevel(of descriptor: ContextDescriptorWrapper, in image: MachOFile) throws -> [Int]? {
        var countsInnermostFirst: [Int] = []
        var current: ContextDescriptorWrapper? = descriptor
        while let context = current {
            if case .type = context {
                let genericContext = try context.genericContext(in: image)
                let ownParameters = genericContext?.currentParameters ?? []
                guard ownParameters.allSatisfy(\.hasKeyArgument) else { return nil }
                countsInnermostFirst.append(ownParameters.count)
            }
            current = try context.parent(in: image)?.resolved
        }
        return countsInnermostFirst.reversed()
    }

    /// Wraps `node`'s nominal chain in `boundGeneric*` nodes level by level,
    /// innermost last, spelling the parent the way the demangler does: a
    /// bound parent sits inside a `.type` envelope, an unbound one stands
    /// bare.
    private func bound(_ node: Node, keyParameterCountsByLevel: ArraySlice<Int>, arguments: ArraySlice<Node>) -> Node? {
        guard Self.nominalKinds.contains(node.kind), let ownCount = keyParameterCountsByLevel.last else {
            return arguments.isEmpty && keyParameterCountsByLevel.allSatisfy({ $0 == 0 }) ? node : nil
        }
        let ownArguments = arguments.suffix(ownCount)
        let parentArguments = arguments.dropLast(ownCount)
        let parentCounts = keyParameterCountsByLevel.dropLast()

        var children = Array(node.children)
        if let parentSlot = children.first {
            let parentNominal: Node? = parentSlot.kind == .type ? parentSlot.firstChild : parentSlot
            if let parentNominal, Self.nominalKinds.contains(parentNominal.kind) {
                guard let boundParent = bound(parentNominal, keyParameterCountsByLevel: parentCounts, arguments: parentArguments) else { return nil }
                let parentIsBound = Self.boundKind(for: parentNominal.kind) == boundParent.kind
                children[0] = parentIsBound || parentSlot.kind == .type ? Node.create(kind: .type, children: [boundParent]) : boundParent
            } else {
                guard parentArguments.isEmpty, parentCounts.allSatisfy({ $0 == 0 }) else { return nil }
            }
        }
        let rebuilt = Node.create(kind: node.kind, children: children)
        guard ownCount > 0 else { return rebuilt }
        guard let boundKind = Self.boundKind(for: node.kind) else { return nil }
        return Node.create(kind: boundKind, children: [
            Node.create(kind: .type, children: [rebuilt]),
            Node.create(kind: .typeList, children: Array(ownArguments)),
        ])
    }

    // MARK: - Mangled names

    private func typeNode(forMangledNamePointerAt address: UInt64) -> Node? {
        guard let offset = environment.addressSpace.offset(forAddress: address) else { return nil }
        do {
            let pointer: RelativeDirectPointer<MangledName> = try machO.readElement(offset: offset)
            guard pointer.isValid else { return nil }
            let mangledName = try pointer.resolve(from: offset, in: machO)
            return try SymbolicDemangler.demangleType(for: mangledName, in: machO)
        } catch {
            return nil
        }
    }

    private func enveloped(_ node: Node) -> Node {
        node.kind == .type ? node : Node.create(kind: .type, children: [node])
    }
}

/// Names a metadata record: its exported `…VN` symbol first, then the
/// record's own descriptor.
package enum MetadataNaming {
    package static func typeNode(forMetadataAt address: UInt64, addressSpace: ThunkAddressSpace, in machO: MachOFile) -> Node? {
        guard let offset = addressSpace.offset(forAddress: address) else { return nil }
        // The metadata symbol first: `…VN` is an *exported* symbol, so it
        // survives the stripping that removes the thunk's own
        // `_get_type_metadata …` symbol, and it carries the complete
        // mangled type. Measured on SwiftUI: one of
        // `ResolvedMenuStyle.Body`'s two candidates is named this way.
        if let node = typeNodeFromMetadataSymbol(atOffset: offset, in: machO) { return node }
        // Otherwise go through the record: a nominal type's metadata
        // stores its context descriptor in the word after the kind.
        return typeNodeFromMetadataRecord(atOffset: offset, in: machO)
    }

    private static func typeNodeFromMetadataSymbol(atOffset offset: Int, in machO: MachOFile) -> Node? {
        guard let symbols = machO.symbols(offset: offset) else { return nil }
        for symbol in symbols {
            guard let symbolNode = try? SymbolicDemangler.demangleSymbol(for: symbol, in: machO) ?? nil else { continue }
            // `…VN` demangles to a `typeMetadata` node wrapping the type.
            guard let metadataNode = symbolNode.first(of: Node.Kind.typeMetadata),
                  let typeNode = metadataNode.firstChild
            else { continue }
            return typeNode
        }
        return nil
    }

    /// Names a nominal type from its metadata record's context descriptor.
    ///
    /// Deliberately **not** through `ValueMetadataProtocol.descriptor(in:)`.
    /// That goes `Pointer.resolve(in:)` → `MachORepresentableWithCache.resolveOffset(at:)`
    /// → `fileOffset(of:)`, which for a shared-cache image answers in the file
    /// accounting while every subsequent read expects the section accounting —
    /// the two differ by a constant and the read fails `offsetOutOfBounds`
    /// (measured on SwiftUI for *both* of `ResolvedMenuStyle.Body`'s
    /// candidates). That is a pre-existing gap in reading absolute pointers
    /// offline, not something this module introduced; the ABI model's own
    /// reads go through *relative* pointers, which are pure arithmetic inside
    /// one accounting and so never hit it.
    ///
    /// `resolveRebase(fileOffset:)` sidesteps it: it answers directly in the
    /// accounting the rest of the read path uses.
    private static func typeNodeFromMetadataRecord(atOffset offset: Int, in machO: MachOFile) -> Node? {
        do {
            let kind: StoredPointer = try machO.readElement(offset: offset)
            guard let metadataKind = MetadataKind(rawValue: numericCast(kind)),
                  metadataKind == .struct || metadataKind == .enum || metadataKind == .optional
            else {
                // A class's descriptor sits at a different offset and a
                // non-nominal metadata record has none at all; naming either
                // from this layout would read an unrelated word as a pointer.
                return nil
            }
            let descriptorFieldOffset = offset + StructMetadata.descriptorOffset
            guard let descriptorOffset = machO.resolveRebase(fileOffset: descriptorFieldOffset) else { return nil }
            // Annotated because `ContextDescriptorWrapper` vends both a
            // `Self`- and a `Self?`-returning `resolve(from:in:)`.
            let descriptor: ContextDescriptorWrapper = try ContextDescriptorWrapper.resolve(from: Int(descriptorOffset), in: machO)
            return try SymbolicDemangler.demangleContext(for: descriptor, in: machO)
        } catch {
            return nil
        }
    }
}
