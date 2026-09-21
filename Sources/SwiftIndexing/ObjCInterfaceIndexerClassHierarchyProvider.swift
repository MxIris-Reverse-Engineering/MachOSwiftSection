import Foundation
import MachOKitExtensions
import ObjCDump
import ObjCIndexing
import ObjCMetadataSource
import SwiftInspection

extension ObjCClassHierarchy {
    /// Builds the hierarchy from the shape the ObjC indexers keep per class:
    /// the class's own `ObjCClassInfo` first, then one per superclass up the
    /// chain (`ObjCInterfaceIndexer.ObjCClassGroup.info`, and the same array
    /// in RuntimeViewer's indexer), plus the image's categories on the class.
    /// Selectors come from each info's method lists; the IMP is an address,
    /// which the member recovery resolves against the image at lookup time.
    /// The adopted protocols' selectors come from the class's and the
    /// categories' protocol lists, inherited protocols included — the
    /// indexers resolve protocols fully, so the set is complete.
    ///
    /// - Parameter isAncestorChainComplete: whether the chain reached a root
    ///   class. The ObjC indexers stop silently where a superclass could not
    ///   be followed, so the caller decides from what it knows — the last
    ///   info having no superclass name is the usual test.
    public init(classInfoChain: [ObjCClassInfo], categoryInfos: [ObjCCategoryInfo] = [], isAncestorChainComplete: Bool) {
        guard let ownInfo = classInfoChain.first else {
            self.init(className: "", methods: [], ancestors: [], isAncestorChainComplete: false)
            return
        }
        var methods: [Method] = []
        var seen: Set<SelectorKey> = []
        func append(_ methodInfos: [ObjCMethodInfo], isClassMethod: Bool) {
            for methodInfo in methodInfos where seen.insert(SelectorKey(selector: methodInfo.name, isClassMethod: isClassMethod)).inserted {
                methods.append(Method(selector: methodInfo.name, isClassMethod: isClassMethod, implementation: methodInfo.imp == 0 ? nil : .address(methodInfo.imp)))
            }
        }
        append(ownInfo.methods, isClassMethod: false)
        append(ownInfo.classMethods, isClassMethod: true)
        for categoryInfo in categoryInfos {
            append(categoryInfo.methods, isClassMethod: false)
            append(categoryInfo.classMethods, isClassMethod: true)
        }
        let ancestors = classInfoChain.dropFirst().map { ancestorInfo in
            Ancestor(className: ancestorInfo.name, instanceSelectors: Set(ancestorInfo.methods.map(\.name)), classSelectors: Set(ancestorInfo.classMethods.map(\.name)), adoptedProtocolSelectors: Self.protocolSelectors(of: ancestorInfo.protocols))
        }
        let unresolvedAncestorName = isAncestorChainComplete ? nil : classInfoChain.last?.superClassName

        self.init(
            className: ownInfo.name,
            methods: methods,
            ancestors: ancestors,
            isAncestorChainComplete: isAncestorChainComplete,
            unresolvedAncestorName: unresolvedAncestorName,
            adoptedProtocolSelectors: Self.protocolSelectors(of: ownInfo.protocols + categoryInfos.flatMap(\.protocols))
        )
    }

    /// The requirements of `protocolInfos` and, recursively, of the
    /// protocols they inherit — the indexers resolve protocols fully, so the
    /// set is complete.
    private static func protocolSelectors(of protocolInfos: [ObjCProtocolInfo]) -> AdoptedProtocolSelectors {
        var instanceSelectors: Set<String> = []
        var classSelectors: Set<String> = []
        var visitedProtocolNames: Set<String> = []
        func collect(_ protocolInfos: [ObjCProtocolInfo]) {
            for protocolInfo in protocolInfos where visitedProtocolNames.insert(protocolInfo.name).inserted {
                instanceSelectors.formUnion(protocolInfo.methods.map(\.name))
                instanceSelectors.formUnion(protocolInfo.optionalMethods.map(\.name))
                classSelectors.formUnion(protocolInfo.classMethods.map(\.name))
                classSelectors.formUnion(protocolInfo.optionalClassMethods.map(\.name))
                collect(protocolInfo.protocols)
            }
        }
        collect(protocolInfos)
        return AdoptedProtocolSelectors(instanceSelectors: instanceSelectors, classSelectors: classSelectors, isComplete: true)
    }

    private struct SelectorKey: Hashable {
        let selector: String
        let isClassMethod: Bool
    }
}

/// Hands the class groups of a prepared `ObjCIndexing.ObjCInterfaceIndexer`
/// to the ObjC member recovery (evolution proposals
/// `objc-ancestor-override-recovery` and `objc-member-selector-recovery`),
/// so a host that already indexed the image's ObjC side does not pay for the
/// library reading the same method lists again. Register it with
/// `SwiftDeclarationIndexer.registerObjCClassHierarchyProvider(_:)` (or
/// `ObjCClassHierarchyProviderStore` directly) for the image the indexer was
/// prepared on.
///
/// A host with its own ObjC indexer (RuntimeViewer) conforms that indexer to
/// `ObjCClassHierarchyProviding` instead, converting its per-class info chain
/// through `ObjCClassHierarchy.init(classInfoChain:categoryInfos:isAncestorChainComplete:)`.
public final class ObjCInterfaceIndexerClassHierarchyProvider<MachO: ObjCMetadataSource & Sendable>: ObjCClassHierarchyProviding, @unchecked Sendable {
    public let indexer: ObjCInterfaceIndexer<MachO>

    private let lock = NSLock()
    private var categoryInfosByClassName: [String: [ObjCCategoryInfo]]?

    /// - Parameter indexer: an indexer whose `prepare()` has completed; a
    ///   class the indexer has not seen answers `nil`, and the library's own
    ///   reader takes over for it — including for a class another image
    ///   defines and this image only extends through categories, which the
    ///   reader can follow into a dyld cache or the running process.
    public init(indexer: ObjCInterfaceIndexer<MachO>) {
        self.indexer = indexer
    }

    public func objcClassHierarchy(forClassNamed runtimeName: String) -> ObjCClassHierarchy? {
        guard let classGroup = indexer.classGroup(forName: runtimeName) else { return nil }
        // The indexer's chain stops where a superclass could not be followed
        // (a standalone file's bound dependency); a chain that ends on a class
        // with no superclass reached the root.
        let isAncestorChainComplete = classGroup.info.last?.superClassName == nil
        return ObjCClassHierarchy(classInfoChain: classGroup.info, categoryInfos: categoryInfos(forClassNamed: runtimeName), isAncestorChainComplete: isAncestorChainComplete)
    }

    /// The indexer files categories under their own unique names; grouping
    /// them by target class happens once, on first use.
    private func categoryInfos(forClassNamed runtimeName: String) -> [ObjCCategoryInfo] {
        lock.lock()
        defer { lock.unlock() }
        if categoryInfosByClassName == nil {
            var grouped: [String: [ObjCCategoryInfo]] = [:]
            for categoryName in indexer.categoryNames.sorted() {
                guard let categoryGroup = indexer.categoryGroup(forName: categoryName) else { continue }
                grouped[categoryGroup.info.className, default: []].append(categoryGroup.info)
            }
            categoryInfosByClassName = grouped
        }
        return categoryInfosByClassName?[runtimeName] ?? []
    }
}
