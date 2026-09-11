import Foundation
import FoundationToolbox
import MachOKit
import MachOSwiftSection
import Demangling
import OrderedCollections
@_spi(Internals) import SwiftInspection

/// Carries the logging floor onto the rewriter.
///
/// `@Loggable` on a **protocol** rather than on the rewriter itself: the
/// rewriter is generic over its `MachO` reader, and applied to a type the macro
/// expands to a static *stored* property, which a generic type cannot have. On a
/// protocol it expands to computed properties in an extension instead, so any
/// conformer — generic or not — gets `logger` and can use `#log`. Same shape as
/// `NestedSpecializationLogging` in `SwiftSpecialization`, which carries the
/// depth-limit diagnostic onto `TypeDefinition` for the same reason.
///
/// `fileprivate`, not `private`: the conformer lives in this file, so file scope
/// is exactly the reach needed — and it keeps a purely local logging helper out
/// of the module's namespace. `private` does NOT work: it caps the generated
/// extension members at `private`, and `#log` expands inside the conformer,
/// where that is not visible.
@Loggable(.fileprivate, subsystem: "com.machoswiftsection.swift-declaration-rendering", category: "OpaqueTypeRewriter")
fileprivate protocol OpaqueTypeRewriteLogging {}

/// Receives an opaque-type rewrite failure so the caller can route it.
///
/// A closure rather than a `SwiftIndexEvents.Dispatcher`: the events live in
/// `SwiftDeclaration`, which *depends on* this module, so naming the type here
/// would close a dependency cycle. The interface path passes a closure that
/// dispatches the event; the dump path (`SwiftDump` has no event machinery at
/// all) passes nothing and takes the os_log floor below.
package typealias OpaqueTypeDegradationReporter = @Sendable (any Error) -> Void

extension Node {
    /// The generic arguments an `opaqueType` node carries, keyed by the depth
    /// each level substitutes.
    ///
    /// Internal rather than private for the same reason the rewriter below is:
    /// reaching this through `resolveOpaqueType(in:)` needs a binary that
    /// happens to carry an opaque type with a matching type list, and what it
    /// pins fails *silently* in rendered output — a mis-collected list either
    /// leaves a parameter unsubstituted (printing `A` / `A1`) or substitutes a
    /// type belonging to a different parameter, and neither raises.
    ///
    /// The walk mirrors `TypeDecoder.decodeMangledType`'s over the same child,
    /// including its stop at the first level that is not a `typeList`.
    static func opaqueTypeGenericArgumentsByDepth(of opaqueTypeNode: Node) -> OrderedDictionary<Int, [Node]> {
        var argumentsByDepth: OrderedDictionary<Int, [Node]> = [:]
        guard let rootTypeListNode = opaqueTypeNode[safeChild: 2] else { return argumentsByDepth }
        for (depth, typeListNode) in rootTypeListNode.children.enumerated() {
            guard typeListNode.isKind(of: .typeList) else { break }
            // `.children`, NOT the node itself: `Node` iterates in PREORDER
            // *including the root*, so `for type in typeListNode` yields the
            // `typeList` node, then every element, then every descendant of
            // every element. Position 0 was therefore the `typeList` node —
            // kind `.typeList`, which the rewriter's `isKind(of: .type)` guard
            // rejects, so parameter 0 was never substituted — and every later
            // parameter read whatever preorder left at its index: the element
            // to its left, or a fragment of that element's subtree.
            argumentsByDepth[depth] = Array(typeListNode.children)
        }
        return argumentsByDepth
    }

    /// Substitutes an opaque type's generic parameters with the concrete
    /// arguments carried by the `opaqueType` node's type list.
    ///
    /// Internal rather than private so the substitution contract can be unit
    /// tested directly: driving it through `resolveOpaqueType(in:)` needs a
    /// binary that happens to contain the right opaque-type shape.
    final class OpaqueTypeGenericParameterRewriter<MachO: MachOSwiftSectionRepresentableWithCache>: Node.Rewriter {
        let machO: MachO

        let typeList: OrderedDictionary<Int, [Node]>

        init(machO: MachO, typeList: OrderedDictionary<Int, [Node]>) {
            self.machO = machO
            self.typeList = typeList
        }

        override func visit(_ node: Node) -> Node {
            if node.isKind(of: .dependentGenericParamType), let depth: Int = node[safeChild: 0]?.index?.cast(), let index: Int = node[safeChild: 1]?.index?.cast(), let type = typeList[depth, default: []][safe: index], type.isKind(of: .type), let substitutedType = type.firstChild {
                // The substituted type's content, NOT `node.firstChild`: a
                // `dependentGenericParamType`'s children are its depth and index
                // literals, so returning the first one hands back the DEPTH and
                // renders as a bare number in generic-argument position
                // (`SwiftUI.StaticIf<A1, 1, C1>`). The `isKind(of: .type)` guard
                // above is what licenses unwrapping `type`'s envelope here.
                return substitutedType.copy()
            } else {
                return node
            }
        }
    }

    private final class OpaqueTypeRewriter<MachO: MachOSwiftSectionRepresentableWithCache>: Node.Rewriter, OpaqueTypeRewriteLogging {
        /// How many times an expansion's own opaque types are expanded in turn.
        ///
        /// Bounded because the relation can cycle — an opaque type's underlying
        /// type may reach that opaque type again — and there is no cheap way to
        /// prove it does not. Eight covers the modifier chains measured in
        /// SwiftUI, where nesting is one layer per `.onChange` / `.task` link.
        static var maximumNestedExpansionDepth: Int { 8 }

        let machO: MachO

        let reportDegradation: OpaqueTypeDegradationReporter?

        /// How many expansions deep this rewriter already is; see
        /// ``expandingNestedOpaqueTypes(in:)``.
        let expansionDepth: Int

        init(machO: MachO, reportDegradation: OpaqueTypeDegradationReporter?, expansionDepth: Int = 0) {
            self.machO = machO
            self.reportDegradation = reportDegradation
            self.expansionDepth = expansionDepth
        }

        /// Expands opaque types that the substitution just brought in.
        ///
        /// `Node.Rewriter` walks bottom-up and never re-visits what `visit`
        /// returns, so an expansion whose underlying type mentions another
        /// `some` type stopped one layer short: the inner reference reached the
        /// reader as `opaque type symbolic reference 0x…`, a raw address where
        /// a type name belongs. Nested `some` is the norm rather than the
        /// exception — a SwiftUI `body` is one opaque type per modifier link.
        ///
        /// At the ceiling the innermost reference is left as it is, which is
        /// the same honest degradation an unresolvable descriptor already gets.
        private func expandingNestedOpaqueTypes(in node: Node) -> Node {
            guard node.contains(Node.Kind.opaqueType) else { return node }
            guard expansionDepth < Self.maximumNestedExpansionDepth else {
                #log(.info, "opaque type expansion reached the nesting limit \(Self.maximumNestedExpansionDepth, privacy: .public) — leaving the innermost reference unexpanded")
                return node
            }
            return OpaqueTypeRewriter(
                machO: machO,
                reportDegradation: reportDegradation,
                expansionDepth: expansionDepth + 1
            ).rewrite(node)
        }

        override func visit(_ node: Node) -> Node {
            do {
                if node.isKind(of: .opaqueType),
                   let firstChild = node.firstChild,
                   firstChild.isKind(of: .opaqueTypeDescriptorSymbolicReference),
                   let offset: Int = firstChild.index?.cast() {
                    // `opaqueTypeDescriptorSymbolicReference` is unified to InProcess in any
                    // MachOImage environment: SymbolicDemangler stashes the descriptor's
                    // absolute in-process pointer bit pattern in Node.index regardless of
                    // whether the descriptor lives in the current image or in a sibling
                    // loaded image (cross-image refs from `View.searchFieldStyle`-style
                    // helpers, weakly-linked descriptors, etc). The whole opaque-type chain —
                    // descriptor read, generic context, underlying type demangle — then runs
                    // through `InProcessContext` via the pointer, matching the Swift runtime's
                    // own scheme of `(ContextDescriptor *)demangleNode->getIndex()`. No
                    // per-image MachO bookkeeping is needed because every read is just a
                    // pointer deref. MachOFile keeps the legacy file-offset semantic because
                    // it lives off-process and has no cross-image issue.
                    let opaqueTypeDescriptor: OpaqueTypeDescriptor
                    let opaqueType: OpaqueType
                    if machO is MachOImage, let absolutePointer = UnsafeRawPointer(bitPattern: offset) {
                        opaqueTypeDescriptor = try absolutePointer.readWrapperElement()
                        opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor)
                    } else {
                        opaqueTypeDescriptor = try OpaqueTypeDescriptor.resolve(from: offset, in: machO)
                        opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO)
                    }

                    // The ordinal — the opaque type's own position among the
                    // `some` results of the declaration that produced it — is
                    // what indexes the underlying-type array. Measured on a
                    // fixture whose single declaration returns
                    // `Pair<some P, some P>`: the descriptor carries four
                    // entries, `[underlying 0, underlying 1, conformance 0,
                    // conformance 1]` — every replacement type first, then the
                    // conformances, which is the order IRGen writes the
                    // underlying substitution map in and the order the
                    // runtime's `_getOpaqueTypeMetadata` reads it back in.
                    // Hardcoding 0 therefore rendered a declaration's second
                    // `some` as its first, silently. Every opaque reference in
                    // SwiftUI's and SwiftUICore's associated-type records
                    // carries ordinal 0, so this is correctness for a shape
                    // those two do not have and a client binary may.
                    let ordinal: Int = node[safeChild: 1]?.index?.cast() ?? 0
                    let allTypeList = Node.opaqueTypeGenericArgumentsByDepth(of: node)
                    if let underlyingTypeArgumentMangledName = opaqueType.underlyingTypeArgumentMangledNames[safe: ordinal] {
                        let underlyingTypeArgumentNode: Node?
                        if machO is MachOImage {
                            underlyingTypeArgumentNode = try? SymbolicDemangler.demangleType(for: underlyingTypeArgumentMangledName)
                        } else {
                            underlyingTypeArgumentNode = try? SymbolicDemangler.demangleType(for: underlyingTypeArgumentMangledName, in: machO)
                        }
                        if let underlyingTypeArgumentNode, underlyingTypeArgumentNode.kind == .type,
                           let firstChild = underlyingTypeArgumentNode.firstChild {
                            let substituted = OpaqueTypeGenericParameterRewriter(machO: machO, typeList: allTypeList).rewrite(firstChild.copy())
                            return expandingNestedOpaqueTypes(in: substituted)
                        }
                    }
                }
            } catch {
                // Never stdout: it carries the generated Swift, so a diagnostic
                // written there corrupts any piped or redirected interface
                // (issue #102). Never a raising `FileHandle` write either — this
                // runs per node inside a rewrite loop, and that overload aborts
                // the host process on a closed or broken stream.
                //
                // The un-rewritten node is returned regardless, so an
                // unresolvable opaque type degrades to its own printing rather
                // than failing the declaration.
                if let reportDegradation {
                    reportDegradation(error)
                } else {
                    #log(.error, "opaque type rewrite failed: \(String(describing: error), privacy: .public)")
                }
            }
            return node
        }
    }

    package func resolveOpaqueType(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        reportingDegradationTo reportDegradation: OpaqueTypeDegradationReporter? = nil
    ) throws -> Node {
        OpaqueTypeRewriter(machO: machO, reportDegradation: reportDegradation).rewrite(self)
    }
}
