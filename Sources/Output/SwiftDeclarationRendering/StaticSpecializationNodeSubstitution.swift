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
    /// `binding`'s arguments substituted and concrete members projected.
    package static func substitutedTypeNode<MachO: MachOSwiftSectionRepresentableWithCache>(
        of typeNode: Node,
        binding: GenericArgumentBinding,
        in machO: MachO
    ) -> Node {
        DependentMemberProjection.projectingConcreteMembers(in: binding.substituting(in: typeNode), in: machO)
    }
}
