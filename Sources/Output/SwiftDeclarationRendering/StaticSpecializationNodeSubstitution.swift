import Demangling
import MachOSwiftSection
@_spi(Internals) import SwiftInspection

/// Binding-driven node substitution for a definition specialized offline
/// (evolution proposal `offline-generic-specialization`) — the counterpart of
/// `SpecializedMetadataNodeSubstitution`, which asks the runtime.
///
/// Offline there is no metadata to resolve a field's type against, only the
/// arguments: they are substituted for the parameters, and a member of a
/// concrete type that leaves behind (`[Swift.Int].Element`) is projected
/// through the conformance records of the image's dependency closure — the
/// answer the runtime gives, read from the records the runtime reads it
/// from. A member no record answers keeps its spelling.
package enum StaticSpecializationNodeSubstitution {
    /// `typeNode` — a field's or an enum payload's declared type — with
    /// `binding`'s arguments substituted and concrete members projected:
    /// through the images `staticFieldLayoutProvider` computes the layout
    /// comments over, when the print has one, so the type and its layout agree
    /// — an iOS binary printed against an iOS cache used to have its layout
    /// computed while its field kept `[Swift.Int].Element?`, the host's macOS
    /// images being no candidates for an iOS root. Without a provider (no
    /// layout comment printed) through the images the opaque rewriter uses.
    package static func substitutedTypeNode<MachO: MachOSwiftSectionRepresentableWithCache>(
        of typeNode: Node,
        binding: GenericArgumentBinding,
        staticFieldLayoutProvider: (any StaticFieldLayoutProvider)?,
        in machO: MachO
    ) -> Node {
        let substitutedNode = binding.substituting(in: typeNode)
        if let projectedNode = staticFieldLayoutProvider?.projectingConcreteMembers(in: substitutedNode) {
            return projectedNode
        }
        return DependentMemberProjection.projectingConcreteMembers(in: substitutedNode, in: machO)
    }
}
