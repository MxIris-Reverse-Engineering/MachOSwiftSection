import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols

// Vtable slot attribution — deciding which member a slot belongs to.
//
// The answer comes from the method descriptor's OWN `Tq` symbol, not from the
// symbols sitting at its implementation address. The implementation route is
// not invertible: identical code folding merges every byte-identical function
// body onto a single address, and asking the index which symbols live there
// answers with all of them at once. SwiftUICore's `0x9330` — the empty `ret`
// body — carries 2878, which is how `SwiftUI.GraphHost`'s four empty vtable
// methods came to print as one correct name plus three coroutine resume
// functions belonging to its nested `GraphHost.Data` struct.
//
// A `Tq` method-descriptor symbol is a data symbol at the descriptor's own
// address, one per member, so folding cannot reach it. Evolution proposal 0006
// already relied on that property as negative evidence for the `final` keyword
// (a member with a `Tq` symbol provably owns a vtable entry); this is the same
// fact used positively.
//
// It is not always available — a stripped image, or a member whose descriptor
// symbol the compiler never emitted — so every entry point here returns `nil`
// rather than throwing, and callers fall back to the implementation route.

extension MethodDescriptor {
    /// The symbols the image's index finds at the descriptor's own offset —
    /// the `Tq` method-descriptor symbol, when the image carries one.
    public func methodDescriptorSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Symbols? {
        machO.symbols(offset: offset)
    }

    /// The member this vtable slot belongs to, recovered from the descriptor's
    /// own `Tq` symbol.
    ///
    /// The result is member-shaped (`global(<entity>)`) — the same shape the
    /// implementation-symbol route yields — so printers and join keys need no
    /// special case for it.
    public func attributedMemberNode<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> NodeReference? {
        guard let symbols = methodDescriptorSymbols(in: machO) else { return nil }
        return MethodDescriptorAttribution.memberNode(forMethodDescriptorSymbols: symbols, in: machO)
    }
}

// Deliberately NOT extended to `MethodOverrideDescriptor` /
// `MethodDefaultOverrideDescriptor`. Those carry no `Tq` symbol of their own —
// they are re-bindings, not declarations — and the descriptor they point at
// belongs to the PARENT class. Attributing an override slot through it answers
// a different question than either consumer asks: the dump prints the
// overriding class's own implementation symbol, and `TypeDefinition.index`
// joins on the subclass's member symbols, so a parent-shaped node matches
// nothing and the `override` keyword disappears from the output entirely
// (caught by `SymbolTestsCoreE2ETests.outputContainsOverrideKeyword`).
// Override slots keep the implementation-address route, which is correct for
// them modulo the same folding ambiguity; their slot NUMBERS come from
// `ParentClassVTableCache` and never depended on symbol attribution.

/// The shared unwrapping behind `attributedMemberNode`.
public enum MethodDescriptorAttribution {
    /// The first symbol among `symbols` that demangles to a method descriptor,
    /// unwrapped to its member.
    ///
    /// A descriptor's own address holds exactly one `Tq` symbol in practice,
    /// but the query is written to skip anything else that may share the
    /// address rather than to assume the first entry is the right one.
    public static func memberNode<MachO: MachOSwiftSectionRepresentableWithCache>(
        forMethodDescriptorSymbols symbols: Symbols,
        in machO: MachO
    ) -> NodeReference? {
        for symbol in symbols {
            guard let node = SymbolicDemangler.demangleSymbolReference(for: symbol, in: machO),
                  let memberNode = memberNode(unwrappingMethodDescriptorNode: node, in: machO) else { continue }
            return memberNode
        }
        return nil
    }

    /// Rewrites `global(methodDescriptor(<entity>))` into `global(<entity>)`.
    ///
    /// Printed as-is, a method-descriptor tree reads "method descriptor for
    /// X" rather than X; every consumer wants the member itself. The rebuilt
    /// tree is interned through `InternedNodeReferenceCache` (never a bare
    /// `NodeReference(interning:)`) so it shares the image's store, and the
    /// intermediate tree is transient because it is consumed by that interning
    /// and dropped.
    static func memberNode<MachO: MachOSwiftSectionRepresentableWithCache>(
        unwrappingMethodDescriptorNode node: NodeReference,
        in machO: MachO
    ) -> NodeReference? {
        guard let methodDescriptorNode = node.first(of: .methodDescriptor),
              let entityNode = methodDescriptorNode.children.first else { return nil }
        let memberTree = Node.createTransient(kind: .global, child: entityNode.materialize())
        return InternedNodeReferenceCache.shared.reference(interning: memberTree, in: machO)
    }
}
