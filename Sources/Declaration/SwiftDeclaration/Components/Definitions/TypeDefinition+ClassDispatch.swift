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
    func classDispatchLookups(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDispatchLookups {
        var lookups = ClassDispatchLookups()
        guard case .class(let classDescriptor) = typeContextDescriptorWrapper else { return lookups }
        let classWrapper = try Class(descriptor: classDescriptor, in: machO.context)
        var visitedNodes: OrderedSet<StructuralNodeReferenceKey> = []
        let typeNode = try SymbolicDemangler.demangleContext(for: .type(.class(classWrapper.descriptor)), in: machO.context)
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
            if let attributedMember = descriptor.attributedMember(in: machO) {
                node = attributedMember.memberNode
                if let slotMemberSymbol = vtableSlotMemberSymbol(for: descriptor, attributedMember: attributedMember, in: machO) {
                    lookups.vtableSlotMemberSymbols.append(slotMemberSymbol)
                }
            } else if let symbols = descriptor.implementationSymbols(in: machO),
                      let overrideSymbol = demangledOverrideSymbol(for: symbols, typeNode: typeNode, visitedNodes: visitedNodes, in: machO) {
                node = overrideSymbol.demangledNode
            } else {
                continue
            }
            visitedNodes.append(StructuralNodeReferenceKey(node))
            let joinKey = memberJoinKey(for: node, in: machO.context)
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
            let joinKey = memberJoinKey(for: node, in: machO.context)
            lookups.methodDescriptorLookup[joinKey] = .methodOverride(descriptor)

            if let vtableSlot = try? parentVTableCache.slotIndex(for: descriptor, in: machO.context) {
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
            lookups.methodDescriptorLookup[memberJoinKey(for: node, in: machO.context)] = .methodDefaultOverride(descriptor)
        }
        return lookups
    }

    /// The symbol a vtable slot's member would carry, built from the slot's
    /// `Tq` symbol for the member builders to fall back to when the image
    /// has no implementation symbol for it (evolution proposal
    /// `interface-descriptor-only-vtable-members`): the implementation's
    /// mangled name at the implementation's entry point.
    ///
    /// `nil` for a slot there is no member to build from:
    /// - an ABI tombstone — a null implementation, the body removed by
    ///   dead-method elimination and the slot kept; this image holds no code
    ///   for the member, and the dump already lists the slot as such;
    /// - a `modify` / `read` coroutine: the symbol index never files those
    ///   accessors as members, so the interface never prints them for a
    ///   class whose symbols are intact either;
    /// - a `Tq` symbol not spelled with the suffix.
    private func vtableSlotMemberSymbol(
        for descriptor: MethodDescriptor,
        attributedMember: MethodDescriptorAttribution.AttributedMember,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> DemangledSymbol? {
        switch descriptor.flags.kind {
        case .method,
             .`init`,
             .getter,
             .setter:
            break
        case .modifyCoroutine,
             .readCoroutine:
            return nil
        }
        guard let implementationOffset = descriptor.implementationOffset,
              let implementationSymbolName = attributedMember.implementationSymbolName else { return nil }
        // An async method's slot holds its async function pointer — the `Tu`
        // constant a caller reads the context size from — not its code; the
        // implementation symbol sits where that record points.
        let entryOffset = descriptor.flags.isAsync ? asyncFunctionEntryOffset(ofAsyncFunctionPointerAt: implementationOffset, in: machO) ?? implementationOffset : implementationOffset
        return DemangledSymbol(symbol: Symbol(offset: entryOffset, name: implementationSymbolName), demangledNode: attributedMember.memberNode)
    }

    /// The code an async function pointer points to, or `nil` when the
    /// record cannot be read.
    private func asyncFunctionEntryOffset(ofAsyncFunctionPointerAt offset: Int, in machO: some MachOSwiftSectionRepresentableWithCache) -> Int? {
        do {
            // Annotated: the optional-returning overload reads another shape.
            let asyncFunctionPointer: AsyncFunctionPointer = try AsyncFunctionPointer.resolve(at: offset, in: machO.context)
            return asyncFunctionPointer.resolvedDirectOffset(from: \.function)
        } catch {
            return nil
        }
    }
}
