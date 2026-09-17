import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols

/// The dynamic-dispatch facts a class's vtable and override tables give up,
/// in the two forms the member builders join against.
///
/// Empty for every non-class: a struct or enum has no dispatch to describe,
/// and the builders then attribute no method descriptor to any member. The
/// default value is what `DefinitionBuilder`'s global / extension / protocol
/// callers pass by omission.
///
/// The two keyings are not interchangeable, and their order of use is the
/// attribution evidence order `TypeDefinition.classDispatchLookups(in:)`
/// documents: the node keys come from each descriptor's own `Tq` symbol —
/// one per member, at the descriptor's own address, which identical code
/// folding cannot reach — while the implementation-offset keys come from the
/// implementation address, which folding makes non-invertible and which is
/// therefore populated only for globally unique addresses.
package struct ClassDispatchLookups {
    /// Member node → its method descriptor. Keyed structurally
    /// (`StructuralNodeReferenceKey`, not a bare `NodeReference`) because the
    /// keys and the look-ups come from different node stores.
    package var methodDescriptorLookup: [StructuralNodeReferenceKey: MethodDescriptorWrapper] = [:]

    /// Member node → its vtable slot index.
    package var vtableOffsetLookup: [StructuralNodeReferenceKey: Int] = [:]

    /// Implementation file offset → method descriptor, the fallback route for
    /// members whose node-based match failed. Only globally unique addresses
    /// are entered.
    package var implementationOffsetDescriptorLookup: [Int: MethodDescriptorWrapper] = [:]

    /// Implementation file offset → vtable slot index, same fallback.
    package var implementationOffsetVTableSlotLookup: [Int: Int] = [:]

    /// The `final` recovery evidence gate (evolution proposal 0006): only a
    /// non-actor class whose vtable trailing objects are present can testify
    /// that a descriptor-less member is `final` — actors cannot be subclassed,
    /// and a class without a vtable header is indistinguishable from a `final`
    /// class, so both stay unmarked.
    package var canRecoverFinalMembers: Bool = false

    package init() {}

    /// The dispatch facts for one member symbol: its method descriptor and
    /// vtable slot, node key first and the implementation offset as the
    /// fallback. This pairing is the join every member builder performs, and
    /// the fallback must stay second — a folded implementation address would
    /// otherwise outrank the member's own `Tq` evidence.
    package func dispatch(
        forMemberNode node: NodeReference,
        implementationOffset: Int
    ) -> (methodDescriptor: MethodDescriptorWrapper?, vtableOffset: Int?) {
        let nodeKey = StructuralNodeReferenceKey(node)
        return (
            methodDescriptorLookup[nodeKey] ?? implementationOffsetDescriptorLookup[implementationOffset],
            vtableOffsetLookup[nodeKey] ?? implementationOffsetVTableSlotLookup[implementationOffset]
        )
    }
}
