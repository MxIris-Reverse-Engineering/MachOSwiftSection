import Demangling
import MachOSwiftSection
import OrderedCollections
import SwiftDeclarationRendering
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension TypeDefinition {
    /// The dynamic-dispatch lookups this type's vtable and override tables
    /// yield — empty for everything that is not a class.
    ///
    /// The vtable / override tables live in the class wrapper's trailing
    /// objects, so this is the one place indexing has to materialize the full
    /// wrapper — once, as a local, released when this function returns
    /// (materialization discipline, proposal 0002).
    func classDispatchLookups<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ClassDispatchLookups {
        var lookups = ClassDispatchLookups()
        guard case .class(let classDescriptor) = typeContextDescriptorWrapper else { return lookups }
        let classWrapper = try Class(descriptor: classDescriptor, in: machO)
        var visitedNodes: OrderedSet<StructuralNodeReferenceKey> = []
        let typeNode = try SymbolicDemangler.demangleContext(for: .type(.class(classWrapper.descriptor)), in: machO)
        let vtableBaseOffset = classWrapper.vTableDescriptorHeader.map { Int($0.layout.vTableOffset) }
        lookups.canRecoverFinalMembers = classWrapper.vTableDescriptorHeader != nil && !classDescriptor.isActor

        // Build offset-based fallback lookups. Uniqueness must be checked against
        // ALL descriptor kinds (method + override + defaultOverride), because
        // trampolines/thunks/shared implementations can have multiple descriptors
        // pointing at the same impl address. If the impl is not globally unique,
        // we cannot use offset-based fallback — we would not know which descriptor
        // to associate the symbol with.
        // A null implementation is the norm, not an anomaly — dead-method
        // elimination removes the body and keeps the slot — so a descriptor
        // without one is SKIPPED, never a reason to abandon the type.
        var implementationOffsetCounts: [Int: Int] = [:]
        for descriptor in classWrapper.methodDescriptors {
            guard let implementationOffset = descriptor.implementationOffset else { continue }
            implementationOffsetCounts[implementationOffset, default: 0] += 1
        }
        for descriptor in classWrapper.methodOverrideDescriptors {
            guard let implementationOffset = descriptor.implementationOffset else { continue }
            implementationOffsetCounts[implementationOffset, default: 0] += 1
        }
        for descriptor in classWrapper.methodDefaultOverrideDescriptors {
            guard let implementationOffset = descriptor.implementationOffset else { continue }
            implementationOffsetCounts[implementationOffset, default: 0] += 1
        }
        for (index, descriptor) in classWrapper.methodDescriptors.enumerated() {
            guard let implementationOffset = descriptor.implementationOffset else { continue }
            // Only use offset-based fallback for globally unique implementation addresses
            if implementationOffsetCounts[implementationOffset] == 1 {
                lookups.implementationOffsetDescriptorLookup[implementationOffset] = .method(descriptor)
                if let vtableBaseOffset {
                    lookups.implementationOffsetVTableSlotLookup[implementationOffset] = vtableBaseOffset + index
                }
            }
        }

        // Attribution evidence order, same as the dump path's
        // `ClassDumper`: the descriptor's own `Tq` symbol first — one per
        // member, at the descriptor's own address, so identical code
        // folding cannot reach it — and the symbols at the implementation
        // address only as a fallback, since folding makes that mapping
        // non-invertible.
        for (index, descriptor) in classWrapper.methodDescriptors.enumerated() {
            let node: NodeReference
            if let attributedNode = descriptor.attributedMemberNode(in: machO) {
                node = attributedNode
            } else if let symbols = descriptor.implementationSymbols(in: machO),
                      let overrideSymbol = demangledOverrideSymbol(for: symbols, typeNode: typeNode, visitedNodes: visitedNodes, in: machO) {
                node = overrideSymbol.demangledNode
            } else {
                continue
            }
            visitedNodes.append(StructuralNodeReferenceKey(node))
            let joinKey = memberJoinKey(for: node, in: machO)
            lookups.methodDescriptorLookup[joinKey] = .method(descriptor)
            if let vtableBaseOffset {
                lookups.vtableOffsetLookup[joinKey] = vtableBaseOffset + index
            }
        }
        var parentVTableCache = ParentClassVTableCache()

        for descriptor in classWrapper.methodOverrideDescriptors {
            // Override slots keep the implementation-address route: the
            // join below is against THIS class's member symbols, which a
            // parent-shaped node from the overridden descriptor's `Tq`
            // symbol never matches. See
            // `Descriptor+MethodDescriptorSymbols.swift`.
            guard let symbols = descriptor.implementationSymbols(in: machO) else { continue }
            guard let overrideSymbol = demangledOverrideSymbol(for: symbols, typeNode: typeNode, visitedNodes: visitedNodes, in: machO) else { continue }
            let node = overrideSymbol.demangledNode
            visitedNodes.append(StructuralNodeReferenceKey(node))
            let joinKey = memberJoinKey(for: node, in: machO)
            lookups.methodDescriptorLookup[joinKey] = .methodOverride(descriptor)

            if let vtableSlot = try? parentVTableCache.slotIndex(for: descriptor, in: machO) {
                lookups.vtableOffsetLookup[joinKey] = vtableSlot
            }
        }
        for descriptor in classWrapper.methodDefaultOverrideDescriptors {
            // Override slots keep the implementation-address route: the
            // join below is against THIS class's member symbols, which a
            // parent-shaped node from the overridden descriptor's `Tq`
            // symbol never matches. See
            // `Descriptor+MethodDescriptorSymbols.swift`.
            guard let symbols = descriptor.implementationSymbols(in: machO) else { continue }
            guard let overrideSymbol = demangledOverrideSymbol(for: symbols, typeNode: typeNode, visitedNodes: visitedNodes, in: machO) else { continue }
            let node = overrideSymbol.demangledNode
            visitedNodes.append(StructuralNodeReferenceKey(node))
            lookups.methodDescriptorLookup[memberJoinKey(for: node, in: machO)] = .methodDefaultOverride(descriptor)
        }
        return lookups
    }
}
