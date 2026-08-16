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
        let machO: MachO

        let reportDegradation: OpaqueTypeDegradationReporter?

        init(machO: MachO, reportDegradation: OpaqueTypeDegradationReporter?) {
            self.machO = machO
            self.reportDegradation = reportDegradation
        }

        override func visit(_ node: Node) -> Node {
            do {
                if node.isKind(of: .opaqueType),
                   let firstChild = node.firstChild,
                   firstChild.isKind(of: .opaqueTypeDescriptorSymbolicReference),
                   let offset: Int = firstChild.index?.cast() {
                    // `opaqueTypeDescriptorSymbolicReference` is unified to InProcess in any
                    // MachOImage environment: MetadataReader stashes the descriptor's
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

                    var allTypeList: OrderedDictionary<Int, [Node]> = [:]
                    if let rootTypeListNode = node[safeChild: 2] {
                        for (depth, typeList) in rootTypeListNode.children.enumerated() {
                            for type in typeList {
                                allTypeList[depth, default: []].append(type)
                            }
                        }
                    }
                    if let underlyingTypeArgumentMangledName = opaqueType.underlyingTypeArgumentMangledNames[safe: 0] {
                        let underlyingTypeArgumentNode: Node?
                        if machO is MachOImage {
                            underlyingTypeArgumentNode = try? MetadataReader.demangleType(for: underlyingTypeArgumentMangledName)
                        } else {
                            underlyingTypeArgumentNode = try? MetadataReader.demangleType(for: underlyingTypeArgumentMangledName, in: machO)
                        }
                        if let underlyingTypeArgumentNode, underlyingTypeArgumentNode.kind == .type,
                           let firstChild = underlyingTypeArgumentNode.firstChild {
                            return OpaqueTypeGenericParameterRewriter(machO: machO, typeList: allTypeList).rewrite(firstChild.copy())
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
