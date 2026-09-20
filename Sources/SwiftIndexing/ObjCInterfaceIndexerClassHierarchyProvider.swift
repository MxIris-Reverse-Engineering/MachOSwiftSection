import MachOKitExtensions
import ObjCDump
import ObjCIndexing
import ObjCMetadataSource
import SwiftInspection

extension ObjCClassHierarchy {
    /// Builds the hierarchy from the shape the ObjC indexers keep per class:
    /// the class's own `ObjCClassInfo` first, then one per superclass up the
    /// chain (`ObjCInterfaceIndexer.ObjCClassGroup.info`, and the same array
    /// in RuntimeViewer's indexer). Selectors come from each info's method
    /// lists; the IMP is an address, which the override recovery resolves
    /// against the image at lookup time.
    ///
    /// - Parameter isAncestorChainComplete: whether the chain reached a root
    ///   class. The ObjC indexers stop silently where a superclass could not
    ///   be followed, so the caller decides from what it knows — the last
    ///   info having no superclass name is the usual test.
    public init(classInfoChain: [ObjCClassInfo], isAncestorChainComplete: Bool) {
        guard let ownInfo = classInfoChain.first else {
            self.init(className: "", methods: [], ancestors: [], isAncestorChainComplete: false)
            return
        }
        var methods: [Method] = ownInfo.methods.map { methodInfo in
            Method(selector: methodInfo.name, isClassMethod: false, implementation: methodInfo.imp == 0 ? nil : .address(methodInfo.imp))
        }
        methods += ownInfo.classMethods.map { methodInfo in
            Method(selector: methodInfo.name, isClassMethod: true, implementation: methodInfo.imp == 0 ? nil : .address(methodInfo.imp))
        }
        let ancestors = classInfoChain.dropFirst().map { ancestorInfo in
            Ancestor(className: ancestorInfo.name, instanceSelectors: Set(ancestorInfo.methods.map(\.name)), classSelectors: Set(ancestorInfo.classMethods.map(\.name)))
        }
        let unresolvedAncestorName = isAncestorChainComplete ? nil : classInfoChain.last?.superClassName
        self.init(className: ownInfo.name, methods: methods, ancestors: ancestors, isAncestorChainComplete: isAncestorChainComplete, unresolvedAncestorName: unresolvedAncestorName)
    }
}

/// Hands the class groups of a prepared `ObjCIndexing.ObjCInterfaceIndexer`
/// to the ObjC-ancestor override recovery (evolution proposal
/// `objc-ancestor-override-recovery`), so a host that already indexed the
/// image's ObjC side does not pay for the library reading the same method
/// lists again. Register it with `SwiftDeclarationIndexer.registerObjCClassHierarchyProvider(_:)`
/// (or `ObjCClassHierarchyProviderStore` directly) for the image the indexer
/// was prepared on.
///
/// A host with its own ObjC indexer (RuntimeViewer) conforms that indexer to
/// `ObjCClassHierarchyProviding` instead, converting its per-class info chain
/// through `ObjCClassHierarchy.init(classInfoChain:isAncestorChainComplete:)`.
public final class ObjCInterfaceIndexerClassHierarchyProvider<MachO: ObjCMetadataSource & Sendable>: ObjCClassHierarchyProviding {
    public let indexer: ObjCInterfaceIndexer<MachO>

    /// - Parameter indexer: an indexer whose `prepare()` has completed; a
    ///   class the indexer has not seen answers `nil`, and the library's own
    ///   reader takes over for it.
    public init(indexer: ObjCInterfaceIndexer<MachO>) {
        self.indexer = indexer
    }

    public func objcClassHierarchy(forClassNamed runtimeName: String) -> ObjCClassHierarchy? {
        guard let classGroup = indexer.classGroup(forName: runtimeName) else { return nil }
        // The indexer's chain stops where a superclass could not be followed
        // (a standalone file's bound dependency); a chain that ends on a class
        // with no superclass reached the root.
        let isAncestorChainComplete = classGroup.info.last?.superClassName == nil
        return ObjCClassHierarchy(classInfoChain: classGroup.info, isAncestorChainComplete: isAncestorChainComplete)
    }
}
