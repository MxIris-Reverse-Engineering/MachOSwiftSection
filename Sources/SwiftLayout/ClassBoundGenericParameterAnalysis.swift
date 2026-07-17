import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// Derives, from a generic type descriptor's requirement signature, the set of
/// generic parameters whose stored representation is known to be a single
/// object reference **without any substitution**: parameters constrained to a
/// class layout (`T: AnyObject`), to a superclass (`T: SomeClass`), or to a
/// class-bound protocol (`T: SomeClassBoundProtocol`, `T: NSCopying`).
///
/// Every class instantiation of such a parameter has the identical field
/// layout (one pointer — size/stride/alignment 8, extra inhabitants
/// `swift_getHeapObjectExtraInhabitantCount`), so a field typed by the
/// parameter — and every field after it — can be laid out exactly even when
/// the type is dumped *unspecialized*. The substitution environment consumes
/// the result: an unsubstituted `dependentGenericParamType` whose `(depth,
/// index)` is in the set rewrites to a placeholder class node instead of
/// degrading (see `GenericArgumentEnvironment`).
///
/// The requirement list read here is the descriptor's cumulative canonical
/// signature (inherited parent-context requirements included), and requirement
/// parameter references carry absolute `(depth, index)` coordinates — the same
/// coordinates field records use — so nested generic contexts need no extra
/// bookkeeping.
enum ClassBoundGenericParameterAnalysis {
    /// The `(depth, index)` keys of every class-bound generic parameter of
    /// `descriptor`, or `[]` for a non-generic descriptor (a fast flag check)
    /// or one whose generic context cannot be read.
    static func classBoundParameterKeys<MachO: MachOSwiftSectionRepresentableWithCache>(
        of descriptor: some TypeContextDescriptorProtocol,
        in image: ImageReference<MachO>,
        imageUniverse: ImageUniverse<MachO>
    ) -> Set<GenericParameterKey> {
        guard let genericContext = try? descriptor.genericContext(in: image.machO) else { return [] }
        var classBoundParameterKeys: Set<GenericParameterKey> = []
        for requirement in genericContext.requirements {
            // A pack requirement (`repeat each T: AnyObject`) constrains each
            // element to a pointer, but the pack's arity stays unknown — the
            // dependent fields cannot be laid out, so the parameter is not
            // marked. (Marking it would still be layout-safe — the expansion
            // machinery degrades on a non-pack count — but is never useful.)
            guard !requirement.layout.flags.contains(.isPackRequirement) else { continue }
            guard isClassBound(requirement, in: image, imageUniverse: imageUniverse) else { continue }
            // Only a constraint on the parameter *itself* pins its storage: a
            // constraint on a dependent member (`T.Element: AnyObject`) says
            // nothing about `T`.
            guard let parameterKey = bareParameterKey(of: requirement, in: image.machO) else { continue }
            classBoundParameterKeys.insert(parameterKey)
        }
        return classBoundParameterKeys
    }

    /// The `(depth, index)` of a requirement whose subject is a bare generic
    /// parameter, or `nil` when the subject is a dependent member type (or
    /// cannot be demangled).
    private static func bareParameterKey<MachO: MachOSwiftSectionRepresentableWithCache>(
        of requirement: GenericRequirementDescriptor,
        in machO: MachO
    ) -> GenericParameterKey? {
        guard
            let parameterMangledName = try? requirement.paramMangledName(in: machO),
            let parameterNode = try? MetadataReader.demangleType(for: parameterMangledName, in: machO)
        else { return nil }
        let unwrapped = parameterNode.kind == .type ? (parameterNode.firstChild ?? parameterNode) : parameterNode
        guard
            unwrapped.kind == .dependentGenericParamType,
            let depth = unwrapped.firstChild?.index,
            let index = unwrapped.children.at(1)?.index
        else { return nil }
        return GenericParameterKey(depth: depth, index: index)
    }

    /// Whether a requirement forces its subject to be a class reference:
    /// a `.layout(.class)` constraint, a superclass bound, or conformance to a
    /// class-bound protocol.
    private static func isClassBound<MachO: MachOSwiftSectionRepresentableWithCache>(
        _ requirement: GenericRequirementDescriptor,
        in image: ImageReference<MachO>,
        imageUniverse: ImageUniverse<MachO>
    ) -> Bool {
        switch requirement.layout.flags.kind {
        case .layout:
            guard case .layout(.class)? = try? requirement.resolvedContent(in: image.machO) else { return false }
            return true
        case .baseClass:
            return true
        case .protocol:
            guard case .protocol(let protocolReference)? = try? requirement.resolvedContent(in: image.machO) else { return false }
            return isClassBoundProtocolReference(protocolReference, in: image, imageUniverse: imageUniverse)
        default:
            // `sameType` to a concrete class is a genuine specialization, not a
            // representation constraint — out of scope here.
            return false
        }
    }

    /// Whether a requirement's protocol reference is class-bound. An imported
    /// Objective-C protocol always is; a Swift protocol descriptor carries the
    /// constraint in its flags; a cross-image reference (a bind symbol in a
    /// file-backed image) is recovered by name through the universe, falling
    /// back to "not class-bound" (the dependent fields then degrade, matching
    /// the engine's conservative direction).
    private static func isClassBoundProtocolReference<MachO: MachOSwiftSectionRepresentableWithCache>(
        _ protocolReference: SymbolOrElement<ProtocolDescriptorWithObjCInterop>,
        in image: ImageReference<MachO>,
        imageUniverse: ImageUniverse<MachO>
    ) -> Bool {
        switch protocolReference {
        case .element(let interopProtocol):
            switch interopProtocol {
            case .objc:
                return true
            case .swift(let protocolDescriptor):
                return protocolDescriptor.flags.kindSpecificFlags?.protocolFlags?.classConstraint == .class
            }
        case .symbol(let symbol):
            guard
                let symbolNode = try? MetadataReader.demangleType(for: symbol, in: image.machO),
                let protocolNode = symbolNode.kind == .protocol ? symbolNode : symbolNode.first(of: .protocol),
                let qualifiedProtocolName = NodeTypeNaming.protocolQualifiedName(of: protocolNode)
            else { return false }
            if imageUniverse.resolveProtocolClassConstraint(byQualifiedTypeName: qualifiedProtocolName) == .class {
                return true
            }
            // A Swift-declared `@objc` protocol emits no Swift protocol
            // descriptor; its `__objc_protolist` record is the recognition
            // signal, and such a protocol is always class-bound.
            return imageUniverse.isObjCProtocolDeclared(byQualifiedTypeName: qualifiedProtocolName)
        }
    }
}
