import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Internals) import Demangling

/// The in-process leg of kind-9 accessor-function resolution (evolution
/// proposal `offline-opaque-accessor-thunk-resolution`, follow-up batch).
///
/// A kind-9 `accessorFunctionReference` means "call this function for the
/// metadata", and in-process that is exactly what the runtime does when the
/// program itself asks for the witness. So instead of reading the thunk, the
/// whole witness is handed to `swift_getTypeByMangledNameInContext` the way
/// `swift_getAssociatedTypeWitnessSlow` does it — with the conforming type's
/// descriptor as the context and its generic-argument area as the arguments
/// (the thunk reads that buffer, so it must be the real one, not null) — and
/// the runtime's answer is demangled back into a node. The runtime answers
/// for THIS OS only; the other branch of an availability check is the
/// offline reader's to report.
///
/// Two shapes are refused rather than guessed at. A **generic conformer** has
/// no metadata without arguments, so the runtime cannot instantiate it and
/// the witness has no answer (measured on SwiftUI: 12 of the 17 kind-9
/// witnesses — `Slider`, `Toggle`, `TextField`, `Picker`, …). A **class
/// conformer**'s generic-argument offset is not a constant (the class overload
/// of `RuntimeFunctions.getTypeByMangledNameInContext(_:specializedFrom:in:)`
/// derives it from the descriptor's bounds); no measured kind-9 witness sits
/// on a class, so that leg is deliberately not wired.
package enum InProcessAccessorFunctionResolution {
    /// The witness the runtime gives for `witnessMangledName`, or `nil` when
    /// the conforming type cannot be instantiated without arguments or is not
    /// a value type.
    package static func witnessNode(witnessMangledName: MangledName, conformingTypeName: MangledName, in machOImage: MachOImage) -> Node? {
        // `_mangledTypeName` — the way back from the runtime's answer to a
        // node — is macOS 11 / iOS 14 API, above this package's floor; the
        // same gate `RuntimeFieldLayoutBackend` applies around its calls.
        guard #available(macOS 11, iOS 14, tvOS 14, watchOS 7, *) else { return nil }
        guard let conformingType = try? RuntimeFunctions.getTypeByMangledNameInContext(conformingTypeName, in: machOImage) else { return nil }
        let metadataPointer = unsafeBitCast(conformingType, to: UnsafeRawPointer.self)
        // A class's first word is its isa pointer, which does not fit a
        // `MetadataKind`; the runtime makes the same "larger than the last
        // enumerated kind" test.
        let kindWord = metadataPointer.load(as: UInt.self)
        guard kindWord <= UInt(UInt32.max), let metadataKind = MetadataKind(rawValue: UInt32(kindWord)) else { return nil }

        let witnessType: Any.Type?
        do {
            switch metadataKind {
            case .struct:
                let metadata: StructMetadata = try metadataPointer.readWrapperElement()
                witnessType = try RuntimeFunctions.getTypeByMangledNameInContext(witnessMangledName, specializedFrom: metadata, in: machOImage)
            case .enum, .optional:
                let metadata: EnumMetadata = try metadataPointer.readWrapperElement()
                witnessType = try RuntimeFunctions.getTypeByMangledNameInContext(witnessMangledName, specializedFrom: metadata, in: machOImage)
            default:
                return nil
            }
        } catch {
            return nil
        }
        guard let witnessType,
              let mangledString = _mangledTypeName(witnessType),
              let node = try? demangleAsNodeTransient(mangledString, isType: true)
        else { return nil }
        return node
    }

    /// `resolved` itself unless it still carries a kind-9 reference, the
    /// reader is in-process, and the runtime answers.
    package static func resolvingRemainingReferences(
        in resolved: Node,
        witnessMangledName: MangledName,
        conformingTypeName: MangledName,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> Node {
        guard let machOImage = machO as? MachOImage, resolved.contains(Node.Kind.accessorFunctionReference) else { return resolved }
        return witnessNode(witnessMangledName: witnessMangledName, conformingTypeName: conformingTypeName, in: machOImage) ?? resolved
    }
}

extension Node {
    /// ``resolveOpaqueType(in:reportingDegradationTo:)`` for an
    /// associated-type witness: in-process, a kind-9 reference the rewrite
    /// left in the tree is answered by the runtime (see
    /// ``InProcessAccessorFunctionResolution``); offline the tree comes back
    /// as the rewrite made it.
    package func resolveOpaqueType(
        witnessMangledName: MangledName,
        conformingTypeName: MangledName,
        in machO: some MachOSwiftSectionRepresentableWithCache,
        reportingDegradationTo reportDegradation: OpaqueTypeDegradationReporter? = nil
    ) throws -> Node {
        let resolved = try resolveOpaqueType(in: machO, reportingDegradationTo: reportDegradation)
        return InProcessAccessorFunctionResolution.resolvingRemainingReferences(
            in: resolved,
            witnessMangledName: witnessMangledName,
            conformingTypeName: conformingTypeName,
            in: machO
        )
    }

    /// ``resolveOpaqueTypeCollectingConditionalCandidates(in:reportingDegradationTo:)``
    /// for an associated-type witness, with the same in-process leg as
    /// ``resolveOpaqueType(witnessMangledName:conformingTypeName:in:reportingDegradationTo:)``.
    /// The candidate list is the offline reader's and stays empty in-process.
    package func resolveOpaqueTypeCollectingConditionalCandidates(
        witnessMangledName: MangledName,
        conformingTypeName: MangledName,
        in machO: some MachOSwiftSectionRepresentableWithCache,
        reportingDegradationTo reportDegradation: OpaqueTypeDegradationReporter? = nil
    ) -> OpaqueTypeResolution {
        let resolution = resolveOpaqueTypeCollectingConditionalCandidates(in: machO, reportingDegradationTo: reportDegradation)
        let node = InProcessAccessorFunctionResolution.resolvingRemainingReferences(
            in: resolution.node,
            witnessMangledName: witnessMangledName,
            conformingTypeName: conformingTypeName,
            in: machO
        )
        guard node !== resolution.node else { return resolution }
        return OpaqueTypeResolution(node: node, conditionalCandidates: resolution.conditionalCandidates)
    }
}
