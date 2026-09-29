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

    /// A member symbol for every one of the class's own vtable slots that its
    /// method descriptor's `Tq` symbol names, in slot order — what the member
    /// builders fall back to for a member the image has no implementation
    /// symbol for (evolution proposal
    /// `interface-descriptor-only-vtable-members`). Each stands in for the
    /// implementation symbol: the implementation's mangled name at the
    /// implementation's offset, so everything downstream that derives from
    /// the name — the export verdict, the ObjC method table join, the ABI
    /// identity — reads it as the symbol it replaces.
    ///
    /// A library-evolution image keeps those implementation symbols local and
    /// exports only the `Tj` / `Tq` forms, so once the local symbols are gone
    /// — AppKit in the OS dyld shared cache, or a binary run through
    /// `strip -x` — these are the only record of the class's public methods
    /// and accessors. Use through
    /// `supplementing(_:in:)`, which adds only the members the real symbols do
    /// not already declare.
    package var vtableSlotMemberSymbols: [DemangledSymbol] = []

    package init() {}

    /// `memberSymbols` plus the vtable slot member symbols of `category`
    /// whose member none of `memberSymbols` declares. A real symbol always
    /// wins: the stand-ins only fill in what the image lost.
    package func supplementing(_ memberSymbols: [DemangledSymbol], in category: MemberCategory) -> [DemangledSymbol] {
        let categorySlotSymbols = vtableSlotMemberSymbols.filter { Self.memberCategory(ofMemberNode: $0.demangledNode) == category }
        guard !categorySlotSymbols.isEmpty else { return memberSymbols }
        let declaredEntityKeys = Set(memberSymbols.compactMap(Self.declaredEntityKey(of:)))
        return memberSymbols + categorySlotSymbols.filter { slotSymbol in
            guard let entityKey = Self.declaredEntityKey(of: slotSymbol) else { return false }
            return !declaredEntityKeys.contains(entityKey)
        }
    }

    /// The member a symbol declares, keyed structurally: its entity node,
    /// past the marker a merged-function thunk leads with — the builders fold
    /// a thunk onto the member it stands for, so it declares that member as
    /// much as the canonical symbol does.
    private static func declaredEntityKey(of memberSymbol: DemangledSymbol) -> StructuralNodeReferenceKey? {
        let children = memberSymbol.demangledNode.children
        guard let firstChild = children.first else { return nil }
        if firstChild.kind == .mergedFunction {
            return children.second.map(StructuralNodeReferenceKey.init)
        }
        return StructuralNodeReferenceKey(firstChild)
    }

    /// The builder input a vtable member belongs in, read off its node the
    /// way the symbol index files the same member's implementation symbol —
    /// `nil` for anything the member builders take no part in.
    private static func memberCategory(ofMemberNode node: NodeReference) -> MemberCategory? {
        guard var entityNode = node.children.first else { return nil }
        var isStatic = false
        if entityNode.kind == .static, let staticEntityNode = entityNode.children.first {
            isStatic = true
            entityNode = staticEntityNode
        }
        switch entityNode.kind {
        case .allocator:
            return .allocators
        case .function:
            return isStatic ? .staticFunctions : .functions
        case .getter,
             .setter:
            switch entityNode.children.first?.kind {
            case .variable:
                return isStatic ? .staticVariables : .variables
            case .subscript:
                return isStatic ? .staticSubscripts : .subscripts
            default:
                return nil
            }
        default:
            return nil
        }
    }

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
