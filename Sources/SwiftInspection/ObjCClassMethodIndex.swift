import Foundation
import FoundationToolbox
import MachOKit
import MachOKitExtensions
@_spi(Core) import MachOObjCSection
@_spi(Internals) import MachOCaches
import MachOReading

/// The library's own ``ObjCClassHierarchy`` reader (evolution proposals
/// `objc-ancestor-override-recovery` and `objc-member-selector-recovery`):
/// the fallback behind ``ObjCClassHierarchyProviderStore`` for an image no
/// host registered a provider for.
///
/// Per image, the eager part is one pass over `__objc_classlist` reading only
/// each class object's `class_ro_t` name — the ObjC runtime name → class
/// object table, and for Swift classes the qualified-name → runtime-name
/// table the Swift side needs to ask by (a `TypeDefinition` knows its
/// qualified name, the ObjC side files the class under `_TtC…`) — plus one
/// pass over `__objc_catlist` reading only each category's target class name.
/// Method lists are NOT read here: they are read per class on demand and
/// memoized, so an image's clang classes cost nothing and NSView's two
/// thousand selectors are read once for AppKit's 173 Swift subclasses. An
/// ancestor in another image memoizes in THAT image's storage — AppKit's and
/// SwiftUI's classes share libobjc's `NSObject` — and the memo is keyed by
/// the class object's offset, so it survives the ObjC reader minting a fresh
/// `MachOFile` per superclass hop (identifiers are UUID-keyed, so the shared
/// cache finds the same entry).
///
/// A class's own methods include the categories of the same image that
/// target it (a Swift `extension` with `@objc` members). A category whose
/// class another image defines (SwiftUI's on `NSView`) gets a hierarchy of
/// its own under the target class's name: the category's methods, and the
/// ancestors of the class where the reader can follow the class pointer.
///
/// Cache images and in-process images follow their superclass into other
/// images; a standalone file's superclass is a bind, which the image's
/// ``ObjCAncestorResolver`` follows by name into the file's dependency
/// images (evolution proposal `objc-ancestor-dependency-closure`) — and
/// where no dependency image defines the class, the chain stops there and
/// says so (`isAncestorChainComplete == false`).
@Loggable(.private, subsystem: "com.machoswiftsection.swift-inspection", category: "ObjCClassMethodIndex")
package final class ObjCClassMethodIndex: SharedCache<ObjCClassMethodIndex.Storage>, @unchecked Sendable {
    package static let shared = ObjCClassMethodIndex()

    /// One ancestor's selector sets, memoized per class object.
    struct SelectorSets {
        let className: String
        let instanceSelectors: Set<String>
        let classSelectors: Set<String>
        let protocolSelectors: RawObjCProtocolSelectors
    }

    package final class Storage: @unchecked Sendable {
        /// `class_ro_t` name → class object, every class the image defines.
        let classObjectsByRuntimeName: [String: ObjCClass64]

        /// Swift qualified name → runtime names. More than one entry means
        /// same-named private classes from different files; the lookup then
        /// refuses to guess.
        let runtimeNamesBySwiftQualifiedName: [String: [String]]

        /// Target class `class_ro_t` name → the image's categories on it, in
        /// `__objc_catlist` order.
        let categoriesByTargetClassName: [String: [ObjCCategory64]]

        /// A hierarchy's memo key carries the identity of the ancestor
        /// resolver it was computed under: the chain past a bind is the
        /// resolver's answer, and a resolver over other search paths — or
        /// none — gives another chain for the same class object. The
        /// selector sets are resolver-independent (they never walk).
        fileprivate struct HierarchyMemoKey: Hashable {
            let classOffset: Int?
            let foreignClassName: String?
            let resolverIdentity: UUID?
        }

        private let lock = NSLock()
        private var selectorSetsByClassOffset: [Int: SelectorSets] = [:]
        private var hierarchiesByMemoKey: [HierarchyMemoKey: ObjCClassHierarchy] = [:]

        init(classObjectsByRuntimeName: [String: ObjCClass64], runtimeNamesBySwiftQualifiedName: [String: [String]], categoriesByTargetClassName: [String: [ObjCCategory64]]) {
            self.classObjectsByRuntimeName = classObjectsByRuntimeName
            self.runtimeNamesBySwiftQualifiedName = runtimeNamesBySwiftQualifiedName
            self.categoriesByTargetClassName = categoriesByTargetClassName
        }

        fileprivate func memoizedSelectorSets(forClassOffset offset: Int) -> SelectorSets? {
            lock.lock()
            defer { lock.unlock() }
            return selectorSetsByClassOffset[offset]
        }

        fileprivate func memoize(_ selectorSets: SelectorSets, forClassOffset offset: Int) {
            lock.lock()
            defer { lock.unlock() }
            selectorSetsByClassOffset[offset] = selectorSets
        }

        fileprivate func memoizedHierarchy(for key: HierarchyMemoKey) -> ObjCClassHierarchy? {
            lock.lock()
            defer { lock.unlock() }
            return hierarchiesByMemoKey[key]
        }

        fileprivate func memoize(_ hierarchy: ObjCClassHierarchy, for key: HierarchyMemoKey) {
            lock.lock()
            defer { lock.unlock() }
            hierarchiesByMemoKey[key] = hierarchy
        }
    }

    override package func buildStorage(for machO: some MachORepresentableWithCache) -> Storage? {
        if let machOFile = machO as? MachOFile {
            return Self.build(in: machOFile)
        } else if let machOImage = machO as? MachOImage {
            return Self.build(in: machOImage)
        }
        return nil
    }

    // MARK: - Queries

    /// The runtime names of the Swift classes whose qualified name is
    /// `qualifiedName`; empty when the image defines no such class object
    /// (a generic class has none — it is instantiated at runtime).
    package func runtimeNames(forSwiftClassQualifiedName qualifiedName: String, in machO: some MachORepresentableWithCache) -> [String] {
        storage(in: machO)?.runtimeNamesBySwiftQualifiedName[qualifiedName] ?? []
    }

    /// The hierarchy of the class the image defines under `runtimeName` —
    /// or, for a class another image defines, of the image's categories on
    /// it — or `nil` when there is neither, or no ObjC method of its own
    /// (nothing to attribute — the ancestor walk is skipped).
    package func hierarchy(forRuntimeName runtimeName: String, in machO: some MachORepresentableWithCache) -> ObjCClassHierarchy? {
        if let machOFile = machO as? MachOFile {
            return hierarchy(forRuntimeName: runtimeName, reader: machOFile)
        } else if let machOImage = machO as? MachOImage {
            return hierarchy(forRuntimeName: runtimeName, reader: machOImage)
        }
        return nil
    }

    private func hierarchy(forRuntimeName runtimeName: String, reader: some ObjCImplementationClassReading) -> ObjCClassHierarchy? {
        guard let storage = storage(in: reader) else { return nil }
        let categories = storage.categoriesByTargetClassName[runtimeName] ?? []
        // A file's binds are followed through its ancestor resolver; an
        // in-process image follows its pointers and has none to follow, but
        // its resolver still folds the loaded non-cache images' categories.
        let resolver = ObjCAncestorResolverStore.shared.resolver(forImage: reader)
        let folding = AncestorCategoryFolding(rootReader: reader, rootStorage: storage, resolver: resolver)
        if let classObject = storage.classObjectsByRuntimeName[runtimeName] {
            let memoKey = Storage.HierarchyMemoKey(classOffset: classObject.offset, foreignClassName: nil, resolverIdentity: resolver?.identity)
            if let memoized = storage.memoizedHierarchy(for: memoKey) {
                return memoized
            }
            // Computed OUTSIDE the storage lock: the ancestor walk memoizes into
            // the same storage when an ancestor lives in this image.
            guard let readOnlyData = reader.instanceReadOnlyData(of: classObject) else { return nil }
            var methods: [ObjCClassHierarchy.Method] = reader.methods(of: readOnlyData).map {
                ObjCClassHierarchy.Method(selector: $0.selector, isClassMethod: false, implementation: $0.implementationOffset.map { .offset($0) })
            }
            if let metaClass = reader.metaClass(of: classObject), let metaReadOnlyData = reader.instanceReadOnlyData(of: metaClass) {
                methods += reader.methods(of: metaReadOnlyData).map {
                    ObjCClassHierarchy.Method(selector: $0.selector, isClassMethod: true, implementation: $0.implementationOffset.map { .offset($0) })
                }
            }
            var protocolSelectors = reader.protocolSelectors(of: readOnlyData)
            Self.append(categories, to: &methods, protocolSelectors: &protocolSelectors, in: reader)
            guard !methods.isEmpty else { return nil }

            let chain = ancestors(startingAt: reader.superclassLocation(of: classObject), className: runtimeName, resolver: resolver, folding: folding)
            let hierarchy = ObjCClassHierarchy(
                className: runtimeName,
                methods: methods,
                ancestors: chain.ancestors,
                isAncestorChainComplete: chain.isComplete,
                unresolvedAncestorName: chain.unresolvedAncestorName,
                adoptedProtocolSelectors: protocolSelectors.hierarchyValue
            )
            storage.memoize(hierarchy, for: memoKey)
            return hierarchy
        }

        // No class object of that name here: the image's categories on a
        // class another image defines.
        guard !categories.isEmpty else { return nil }
        let memoKey = Storage.HierarchyMemoKey(classOffset: nil, foreignClassName: runtimeName, resolverIdentity: resolver?.identity)
        if let memoized = storage.memoizedHierarchy(for: memoKey) {
            return memoized
        }
        var methods: [ObjCClassHierarchy.Method] = []
        var protocolSelectors = RawObjCProtocolSelectors(instanceSelectors: [], classSelectors: [], isComplete: true)
        Self.append(categories, to: &methods, protocolSelectors: &protocolSelectors, in: reader)
        guard !methods.isEmpty else { return nil }

        // The class itself is not an ancestor of its own categories (a
        // category cannot override the class's own method — Swift rejects
        // the selector collision), so the walk starts at ITS superclass.
        // The category's class pointer is a rebase inside a cache and a bind
        // in a file; the bind is followed by name like a superclass.
        var chain = AncestorChain(ancestors: [], isComplete: false, unresolvedAncestorName: runtimeName)
        var targetClass: (any ObjCImplementationClassReading, ObjCClass64)? = reader.targetClass(of: categories[0])
        if targetClass == nil, let resolver, let (classImage, classObject) = resolver.classObject(named: runtimeName) {
            targetClass = (classImage, classObject)
        }
        if let (classReader, classObject) = targetClass {
            if let readOnlyData = classReader.instanceReadOnlyData(of: classObject) {
                protocolSelectors.merge(classReader.protocolSelectors(of: readOnlyData))
            } else {
                protocolSelectors.isComplete = false
            }
            chain = ancestors(startingAt: classReader.superclassLocation(of: classObject), className: runtimeName, resolver: resolver, folding: folding)
        } else {
            protocolSelectors.isComplete = false
        }
        let hierarchy = ObjCClassHierarchy(
            className: runtimeName,
            methods: methods,
            ancestors: chain.ancestors,
            isAncestorChainComplete: chain.isComplete,
            unresolvedAncestorName: chain.unresolvedAncestorName,
            adoptedProtocolSelectors: protocolSelectors.hierarchyValue
        )
        storage.memoize(hierarchy, for: memoKey)
        return hierarchy
    }

    /// Continues a hierarchy a host's provider handed over with its chain
    /// broken at a bind — the ObjC indexers stop where a superclass could
    /// not be followed, exactly where the library's reader does — through
    /// the image's ancestor resolver, so the provider seam and the reader
    /// reach the same chain on a standalone file. A complete chain, an
    /// unnamed break, or a name no dependency image defines returns the
    /// hierarchy unchanged.
    package func completingAncestors(of hierarchy: ObjCClassHierarchy, in machO: some MachORepresentableWithCache) -> ObjCClassHierarchy {
        guard !hierarchy.isAncestorChainComplete,
              let unresolvedAncestorName = hierarchy.unresolvedAncestorName,
              let resolver = ObjCAncestorResolverStore.shared.resolver(forImage: machO),
              let (ancestorImage, ancestorClassObject) = resolver.classObject(named: unresolvedAncestorName)
        else { return hierarchy }
        let folding = folding(for: machO, resolver: resolver)
        let chain = ancestors(startingAt: .resolved(ancestorImage, ancestorClassObject), className: hierarchy.className, resolver: resolver, folding: folding)
        return ObjCClassHierarchy(
            className: hierarchy.className,
            methods: hierarchy.methods,
            ancestors: hierarchy.ancestors + chain.ancestors,
            isAncestorChainComplete: chain.isComplete,
            unresolvedAncestorName: chain.unresolvedAncestorName,
            adoptedProtocolSelectors: hierarchy.adoptedProtocolSelectors
        )
    }

    /// Folds the categories' methods and protocols in. A selector the class
    /// list already carries is kept once — a dyld cache pre-attaches an
    /// image's own categories into the class's list-of-lists while
    /// `__objc_catlist` still names them.
    private static func append(_ categories: [ObjCCategory64], to methods: inout [ObjCClassHierarchy.Method], protocolSelectors: inout RawObjCProtocolSelectors, in reader: some ObjCImplementationClassReading) {
        guard !categories.isEmpty else { return }
        var seen: Set<SelectorKey> = Set(methods.map { SelectorKey(selector: $0.selector, isClassMethod: $0.isClassMethod) })
        for category in categories {
            for method in reader.instanceMethods(of: category) where seen.insert(SelectorKey(selector: method.selector, isClassMethod: false)).inserted {
                methods.append(ObjCClassHierarchy.Method(selector: method.selector, isClassMethod: false, implementation: method.implementationOffset.map { .offset($0) }))
            }
            for method in reader.classMethods(of: category) where seen.insert(SelectorKey(selector: method.selector, isClassMethod: true)).inserted {
                methods.append(ObjCClassHierarchy.Method(selector: method.selector, isClassMethod: true, implementation: method.implementationOffset.map { .offset($0) }))
            }
            protocolSelectors.merge(reader.protocolSelectors(of: category))
        }
    }

    private struct SelectorKey: Hashable {
        let selector: String
        let isClassMethod: Bool
    }

    private struct AncestorChain {
        var ancestors: [ObjCClassHierarchy.Ancestor]
        var isComplete: Bool
        var unresolvedAncestorName: String?
    }

    /// Where an ancestor's selector set is completed from beyond its own
    /// image: the root image's categories on it (the class being analyzed
    /// may live next to an `extension NSObject`), and — for a file — the
    /// categories of every standalone file in the root's dependency closure
    /// (`ObjCAncestorResolver.fileCategorySelectors(onClassNamed:)`). A cache
    /// image's categories are pre-attached by dyld and need no folding.
    private struct AncestorCategoryFolding {
        let rootReader: any ObjCImplementationClassReading
        let rootStorage: Storage
        let resolver: ObjCAncestorResolver?

        func selectors(onClassNamed runtimeName: String) -> RawObjCCategorySelectors {
            var result = RawObjCCategorySelectors()
            if let categories = rootStorage.categoriesByTargetClassName[runtimeName], !categories.isEmpty {
                result.merge(ObjCClassMethodIndex.categorySelectors(of: categories, in: rootReader))
            }
            if let resolver {
                result.merge(resolver.fileCategorySelectors(onClassNamed: runtimeName))
            }
            return result
        }
    }

    /// The selectors `categories` add to their target class, protocols
    /// included, read in the image that carries them.
    static func categorySelectors(of categories: [ObjCCategory64], in reader: any ObjCImplementationClassReading) -> RawObjCCategorySelectors {
        func compute<Reader: ObjCImplementationClassReading>(in reader: Reader) -> RawObjCCategorySelectors {
            var result = RawObjCCategorySelectors()
            for category in categories {
                result.instanceSelectors.formUnion(reader.instanceMethods(of: category).map(\.selector))
                result.classSelectors.formUnion(reader.classMethods(of: category).map(\.selector))
                result.protocolSelectors.merge(reader.protocolSelectors(of: category))
            }
            return result
        }
        return compute(in: reader)
    }

    /// Walks the superclass chain from `location` upwards, collecting each
    /// ancestor's selector sets (memoized in the ancestor's own image, then
    /// completed with the categories `folding` sees on it). A bind the
    /// reader cannot follow is handed to `resolver`, which finds the named
    /// class in the file's dependency images; the walk continues in that
    /// image, with the same resolver for its own binds.
    private func ancestors(startingAt location: ObjCSuperclassLocation, className: String, resolver: ObjCAncestorResolver?, folding: AncestorCategoryFolding?) -> AncestorChain {
        var chain = AncestorChain(ancestors: [], isComplete: true, unresolvedAncestorName: nil)
        var location = location
        var hopCount = 0
        walk: while true {
            switch location {
            case .root:
                break walk
            case .unresolvable(let superclassName):
                if let superclassName, let resolver, let (ancestorImage, ancestorClassObject) = resolver.classObject(named: superclassName) {
                    location = .resolved(ancestorImage, ancestorClassObject)
                    continue walk
                }
                chain.isComplete = false
                chain.unresolvedAncestorName = superclassName
                break walk
            case .resolved(let ancestorReader, let ancestorClassObject):
                hopCount += 1
                guard hopCount <= 64 else {
                    // A superclass cycle is corrupt metadata; refuse to spin.
                    #log(.error, "superclass chain of \(className, privacy: .public) exceeds 64 hops; treating it as broken")
                    chain.isComplete = false
                    break walk
                }
                guard let selectorSets = selectorSets(of: ancestorClassObject, in: ancestorReader) else {
                    chain.isComplete = false
                    break walk
                }
                var instanceSelectors = selectorSets.instanceSelectors
                var classSelectors = selectorSets.classSelectors
                var protocolSelectors = selectorSets.protocolSelectors
                if let folded = folding?.selectors(onClassNamed: selectorSets.className), !folded.isEmpty {
                    instanceSelectors.formUnion(folded.instanceSelectors)
                    classSelectors.formUnion(folded.classSelectors)
                    protocolSelectors.merge(folded.protocolSelectors)
                }
                chain.ancestors.append(ObjCClassHierarchy.Ancestor(className: selectorSets.className, instanceSelectors: instanceSelectors, classSelectors: classSelectors, adoptedProtocolSelectors: protocolSelectors.hierarchyValue))
                location = ancestorReader.superclassLocation(of: ancestorClassObject)
            }
        }
        return chain
    }

    private func folding(for machO: some MachORepresentableWithCache, resolver: ObjCAncestorResolver?) -> AncestorCategoryFolding? {
        if let machOFile = machO as? MachOFile, let storage = storage(in: machOFile) {
            return AncestorCategoryFolding(rootReader: machOFile, rootStorage: storage, resolver: resolver)
        }
        if let machOImage = machO as? MachOImage, let storage = storage(in: machOImage) {
            return AncestorCategoryFolding(rootReader: machOImage, rootStorage: storage, resolver: resolver)
        }
        return nil
    }

    /// The selectors `classObject` (living in `reader`'s image) implements,
    /// memoized in that image's storage.
    private func selectorSets(of classObject: ObjCClass64, in reader: any ObjCImplementationClassReading) -> SelectorSets? {
        func compute<Reader: ObjCImplementationClassReading>(in reader: Reader) -> SelectorSets? {
            guard let storage = storage(in: reader) else { return nil }
            if let memoized = storage.memoizedSelectorSets(forClassOffset: classObject.offset) {
                return memoized
            }
            guard let readOnlyData = reader.instanceReadOnlyData(of: classObject), let className = reader.className(of: readOnlyData) else { return nil }
            var instanceSelectors = Set(reader.methods(of: readOnlyData).map(\.selector))
            var classSelectors: Set<String> = []
            if let metaClass = reader.metaClass(of: classObject), let metaReadOnlyData = reader.instanceReadOnlyData(of: metaClass) {
                classSelectors = Set(reader.methods(of: metaReadOnlyData).map(\.selector))
            }
            var protocolSelectors = reader.protocolSelectors(of: readOnlyData)
            // The ancestor's own image may extend it through categories too.
            for category in storage.categoriesByTargetClassName[className] ?? [] {
                instanceSelectors.formUnion(reader.instanceMethods(of: category).map(\.selector))
                classSelectors.formUnion(reader.classMethods(of: category).map(\.selector))
                protocolSelectors.merge(reader.protocolSelectors(of: category))
            }
            let selectorSets = SelectorSets(className: className, instanceSelectors: instanceSelectors, classSelectors: classSelectors, protocolSelectors: protocolSelectors)
            storage.memoize(selectorSets, forClassOffset: classObject.offset)
            return selectorSets
        }
        return compute(in: reader)
    }

    // MARK: - Build

    private static func build(in machO: some ObjCImplementationClassReading) -> Storage {
        var classObjectsByRuntimeName: [String: ObjCClass64] = [:]
        var runtimeNamesBySwiftQualifiedName: [String: [String]] = [:]
        for classObject in machO.objcImplementationClassObjects() ?? [] {
            guard let readOnlyData = machO.instanceReadOnlyData(of: classObject), !readOnlyData.isMetaClass,
                  let runtimeName = machO.className(of: readOnlyData), !runtimeName.isEmpty,
                  classObjectsByRuntimeName[runtimeName] == nil
            else { continue }
            classObjectsByRuntimeName[runtimeName] = classObject
            if classObject.isSwift, let qualifiedName = NodeTypeNaming.swiftClassQualifiedName(fromRuntimeName: runtimeName) {
                runtimeNamesBySwiftQualifiedName[qualifiedName, default: []].append(runtimeName)
            }
        }
        var categoriesByTargetClassName: [String: [ObjCCategory64]] = [:]
        for category in machO.objcCategories() ?? [] {
            guard let targetClassName = machO.targetClassName(of: category), !targetClassName.isEmpty else { continue }
            categoriesByTargetClassName[targetClassName, default: []].append(category)
        }
        return Storage(classObjectsByRuntimeName: classObjectsByRuntimeName, runtimeNamesBySwiftQualifiedName: runtimeNamesBySwiftQualifiedName, categoriesByTargetClassName: categoriesByTargetClassName)
    }
}

/// Where a class's superclass pointer leads.
enum ObjCSuperclassLocation {
    /// The class is a root class (null superclass).
    case root
    /// The superclass, paired with the reader for the image it lives in —
    /// the same image, or another image of the same cache / process.
    case resolved(any ObjCImplementationClassReading, ObjCClass64)
    /// The superclass pointer is a bind into an image this reader cannot
    /// reach (a standalone file's dependency); `String?` is the bound
    /// symbol's class name when the bind names one.
    case unresolvable(String?)
}

/// What categories add to a class: instance and class selectors, and the
/// selectors of the protocols the categories adopt.
struct RawObjCCategorySelectors {
    var instanceSelectors: Set<String> = []
    var classSelectors: Set<String> = []
    var protocolSelectors = RawObjCProtocolSelectors(instanceSelectors: [], classSelectors: [], isComplete: true)

    var isEmpty: Bool {
        instanceSelectors.isEmpty && classSelectors.isEmpty && protocolSelectors.instanceSelectors.isEmpty && protocolSelectors.classSelectors.isEmpty && protocolSelectors.isComplete
    }

    mutating func merge(_ other: RawObjCCategorySelectors) {
        instanceSelectors.formUnion(other.instanceSelectors)
        classSelectors.formUnion(other.classSelectors)
        protocolSelectors.merge(other.protocolSelectors)
    }
}

/// The selectors of a protocol list's protocols (inherited protocols
/// included), before the Swift join.
struct RawObjCProtocolSelectors {
    var instanceSelectors: Set<String>
    var classSelectors: Set<String>
    /// `false` when a protocol could not be followed.
    var isComplete: Bool

    mutating func merge(_ other: RawObjCProtocolSelectors) {
        instanceSelectors.formUnion(other.instanceSelectors)
        classSelectors.formUnion(other.classSelectors)
        isComplete = isComplete && other.isComplete
    }

    /// A selector read as an empty string is a selector the reader could
    /// not read (a method list in another image of an archived cache whose
    /// name strings it does not reach — observed for Foundation's
    /// `NSSecureCoding` from a macOS 15.5 cache's WidgetKit), not a selector:
    /// the set is then incomplete, and no verdict rests on it.
    mutating func insert(instanceSelectors: [String]) {
        for selector in instanceSelectors {
            if selector.isEmpty { isComplete = false } else { self.instanceSelectors.insert(selector) }
        }
    }

    mutating func insert(classSelectors: [String]) {
        for selector in classSelectors {
            if selector.isEmpty { isComplete = false } else { self.classSelectors.insert(selector) }
        }
    }

    var hierarchyValue: ObjCClassHierarchy.AdoptedProtocolSelectors {
        .init(instanceSelectors: instanceSelectors, classSelectors: classSelectors, isComplete: isComplete)
    }
}
