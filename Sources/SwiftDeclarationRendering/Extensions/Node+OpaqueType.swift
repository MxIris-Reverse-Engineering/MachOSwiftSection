import Foundation
import MachOKit
import MachOSwiftSection
import Demangling
import OrderedCollections
@_spi(Internals) import SwiftInspection

extension Node {
    private final class OpaqueTypeGenericParameterRewriter<MachO: MachOSwiftSectionRepresentableWithCache>: Node.Rewriter {
        let machO: MachO

        let typeList: OrderedDictionary<Int, [Node]>

        init(machO: MachO, typeList: OrderedDictionary<Int, [Node]>) {
            self.machO = machO
            self.typeList = typeList
        }

        override func visit(_ node: Node) -> Node {
            if node.isKind(of: .dependentGenericParamType), let depth: Int = node[safeChild: 0]?.index?.cast(), let index: Int = node[safeChild: 1]?.index?.cast(), let type = typeList[depth, default: []][safe: index], type.isKind(of: .type), let firstChild = node.firstChild {
                return firstChild.copy()
            } else {
                return node
            }
        }
    }

    private final class OpaqueTypeRewriter<MachO: MachOSwiftSectionRepresentableWithCache>: Node.Rewriter {
        let machO: MachO

        init(machO: MachO) {
            self.machO = machO
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
                Swift.print(error)
            }
            return node
        }
    }

    package func resolveOpaqueType(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Node {
        OpaqueTypeRewriter(machO: machO).rewrite(self)
    }
}
