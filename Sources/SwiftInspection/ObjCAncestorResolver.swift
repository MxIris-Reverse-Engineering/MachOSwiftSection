import Foundation
import FoundationToolbox
import MachOKit
import MachOKitExtensions
import MachOFoundation
@_spi(Internals) import MachOCaches
@_spi(Core) import MachOObjCSection

/// Follows a standalone file's bound superclass — or a category's bound
/// target class — into the file's dependency images, by ObjC runtime name
/// (evolution proposal `objc-ancestor-dependency-closure`).
///
/// A cache image and an in-process image follow their superclass pointers
/// into other images directly; a file on disk (an app binary, a framework
/// pulled out of a bundle, a simulator runtime's framework) has a bind there,
/// which `ObjCImplementationClassReading.superclassLocation(of:)` reports as
/// `.unresolvable(name)`. The bind names the class (`_OBJC_CLASS_$_UIView`,
/// `_OBJC_CLASS_$__TtC7SwiftUI9Something` — the `class_ro_t` name behind the
/// prefix), and the images the file links are exactly where the class is
/// defined, so the name is looked up in each dependency image's
/// `ObjCClassMethodIndex` name table, in the closure's breadth-first order,
/// first hit wins. A bind resolves against exports, so an image's export
/// trie is asked first — an exact pre-check that spares the class-list read
/// of every image not carrying the class; only the images asked build their
/// name table, the same laziness `SwiftLayout.ImageUniverse` applies to the
/// same closure.
///
/// The dependency images are resolved once, on the first lookup, and every
/// verdict — hit or miss — is memoized by name. One resolver serves every
/// hop of a chain: a superclass found in an explicit file is itself a file
/// whose own superclass is a bind, and the root's transitive closure holds
/// that image too.
@Loggable(.private, subsystem: "com.machoswiftsection.swift-inspection", category: "ObjCAncestorResolver")
public final class ObjCAncestorResolver: @unchecked Sendable {
    /// Distinguishes the hierarchies computed under one resolver from
    /// another's in `ObjCClassMethodIndex`'s per-image memo: a caller that
    /// installs a resolver over no images and later the default one must not
    /// read the first's broken chain back.
    let identity = UUID()

    /// The dependency images, in lookup order: files for a file on disk,
    /// the loaded images for an in-process root (whose superclass pointers
    /// are all real — only the category fold reads those).
    enum DependencyImages {
        case files([MachOFile])
        case loaded([MachOImage])
    }

    private let makeDependencyImages: @Sendable () -> DependencyImages
    private let lock = NSLock()
    private var dependencyImages: DependencyImages?
    private var memoizedClassObjectsByRuntimeName: [String: (MachOFile, ObjCClass64)?] = [:]
    private var memoizedCategorySelectorsByRuntimeName: [String: RawObjCCategorySelectors] = [:]

    /// - Parameter dependencyImages: Produces the images to look in, in
    ///   lookup order; called once, on the first name that reaches a bind.
    public init(dependencyImages: @escaping @Sendable () -> [MachOFile]) {
        self.makeDependencyImages = { .files(dependencyImages()) }
    }

    /// A resolver over `root`'s transitive dependency closure through
    /// `searchPaths` (`DependencyClosure(root:searchPaths:traversal: .transitive)`)
    /// — the same closure every other cross-image consumer of the root reads.
    public convenience init(root: MachOFile, searchPaths: [DependencySearchPath]) {
        self.init {
            DependencyClosure(root: root, searchPaths: searchPaths, traversal: .transitive).images
        }
    }

    /// A resolver over an in-process root's loaded dependencies (the active
    /// dyld's closure). No bind is ever followed through it — every
    /// superclass pointer is real in-process — but the categories of the
    /// non-cache images the process loaded are attached by the runtime into
    /// `class_rw_ext_t`, which the readers do not see, so they are folded
    /// from those images' `__objc_catlist` like a file's.
    public convenience init(inProcessRoot: MachOImage) {
        self.init(loadedImages: { DependencyClosure(root: inProcessRoot, traversal: .transitive).images })
    }

    init(loadedImages: @escaping @Sendable () -> [MachOImage]) {
        self.makeDependencyImages = { .loaded(loadedImages()) }
    }

    /// A resolver over no images: every bind stays unresolvable, exactly the
    /// behavior of a reader with no dependency closure at hand.
    public static let empty = ObjCAncestorResolver(dependencyImages: { [] })

    /// The class object named `runtimeName` and the image defining it, or
    /// `nil` when no dependency image exports such a class.
    package func classObject(named runtimeName: String) -> (MachOFile, ObjCClass64)? {
        lock.lock()
        defer { lock.unlock() }
        if let memoized = memoizedClassObjectsByRuntimeName[runtimeName] {
            return memoized
        }
        if dependencyImages == nil {
            dependencyImages = makeDependencyImages()
        }
        guard case .files(let files) = dependencyImages else {
            memoizedClassObjectsByRuntimeName[runtimeName] = .some(nil)
            return nil
        }
        let exportedName = "_OBJC_CLASS_$_" + runtimeName
        var found: (MachOFile, ObjCClass64)?
        for image in files {
            // A re-export entry (an umbrella framework's) passes here and
            // misses the class list; the defining image follows in the closure.
            guard image.exportTrie?.search(by: exportedName) != nil else { continue }
            guard let classObject = ObjCClassMethodIndex.shared.storage(in: image)?.classObjectsByRuntimeName[runtimeName] else { continue }
            found = (image, classObject)
            break
        }
        if found == nil {
            #log(.info, "no dependency image defines the ObjC class \(runtimeName, privacy: .public); the chain stops there")
        }
        memoizedClassObjectsByRuntimeName[runtimeName] = .some(found)
        return found
    }

    /// The selectors that categories in the file's dependency images add to
    /// the class named `runtimeName`, from the images that are standalone
    /// files. A class read out of a dyld cache already carries the cache's
    /// categories in its own method lists (dyld pre-attaches them); a file's
    /// categories are attached at load time only, so offline they have to be
    /// folded into the ancestor's selector set here — Foundation's
    /// `NSObject (NSKeyValueObserving)` is what makes a simulator-runtime
    /// framework's `observeValue(forKeyPath:of:change:context:)` an override
    /// rather than a member whose selector the compiler would not derive.
    /// Memoized per name; a first lookup builds the name tables of every
    /// file in the closure (one class-list and category-list pass each).
    func fileCategorySelectors(onClassNamed runtimeName: String) -> RawObjCCategorySelectors {
        lock.lock()
        defer { lock.unlock() }
        if let memoized = memoizedCategorySelectorsByRuntimeName[runtimeName] {
            return memoized
        }
        if dependencyImages == nil {
            dependencyImages = makeDependencyImages()
        }
        var result = RawObjCCategorySelectors()
        switch dependencyImages {
        case .files(let files):
            for image in files where !image.isLoadedFromDyldCache {
                guard let categories = ObjCClassMethodIndex.shared.storage(in: image)?.categoriesByTargetClassName[runtimeName], !categories.isEmpty else { continue }
                result.merge(ObjCClassMethodIndex.categorySelectors(of: categories, in: image))
            }
        case .loaded(let images):
            for image in images where !image.header.isInDyldCache {
                guard let categories = ObjCClassMethodIndex.shared.storage(in: image)?.categoriesByTargetClassName[runtimeName], !categories.isEmpty else { continue }
                result.merge(ObjCClassMethodIndex.categorySelectors(of: categories, in: image))
            }
        case nil:
            break
        }
        memoizedCategorySelectorsByRuntimeName[runtimeName] = result
        return result
    }
}

/// Per-image registry of ``ObjCAncestorResolver``s. Same shape as
/// `PropertyWrapperTypeCatalogStore`: the declaration indexer registers a
/// resolver over its configured `dependencySearchPaths` when it prepares an
/// image, the CLI's `dump` registers one over its `--dependency-search-path`
/// options, and a file nobody registered for gets one over the running
/// system's dyld shared cache on first use — so the hierarchy reader, which
/// has no view of anyone's configuration, asks here by image.
public final class ObjCAncestorResolverStore: @unchecked Sendable {
    public static let shared = ObjCAncestorResolverStore()

    private let lock = NSLock()
    private var resolversByImageIdentifier: [AnyHashable: ObjCAncestorResolver] = [:]

    private init() {}

    /// Installs `resolver` for `machO`, replacing any earlier registration —
    /// a default one a lookup created before it included.
    public func register(_ resolver: ObjCAncestorResolver, for machO: some MachORepresentableWithCache) {
        lock.lock()
        defer { lock.unlock() }
        resolversByImageIdentifier[AnyHashable(machO.identifier)] = resolver
    }

    /// A file's resolver: the registered one, else a default over the
    /// running system's dyld shared cache, created on first use.
    public func resolver(for machOFile: MachOFile) -> ObjCAncestorResolver {
        lock.lock()
        defer { lock.unlock() }
        let key = AnyHashable(machOFile.identifier)
        if let existing = resolversByImageIdentifier[key] {
            return existing
        }
        let resolver = ObjCAncestorResolver(root: machOFile, searchPaths: [.systemDyldSharedCache])
        resolversByImageIdentifier[key] = resolver
        return resolver
    }

    /// An in-process image's resolver: the registered one, else a default
    /// over the loaded images, created on first use — consulted for the
    /// category fold only, never for a bind.
    public func resolver(for machOImage: MachOImage) -> ObjCAncestorResolver {
        lock.lock()
        defer { lock.unlock() }
        let key = AnyHashable(machOImage.identifier)
        if let existing = resolversByImageIdentifier[key] {
            return existing
        }
        let resolver = ObjCAncestorResolver(inProcessRoot: machOImage)
        resolversByImageIdentifier[key] = resolver
        return resolver
    }

    /// The resolver for whichever reader kind `machO` is; `nil` for a reader
    /// of another kind. (Named apart from ``resolver(for:)`` on purpose — a
    /// same-labelled generic overload resolved to itself from inside the
    /// cast and recursed.)
    func resolver(forImage machO: some MachORepresentableWithCache) -> ObjCAncestorResolver? {
        if let machOFile = machO as? MachOFile {
            let fileResolver: ObjCAncestorResolver = resolver(for: machOFile)
            return fileResolver
        }
        if let machOImage = machO as? MachOImage {
            let imageResolver: ObjCAncestorResolver = resolver(for: machOImage)
            return imageResolver
        }
        return nil
    }

    public func contains(in machO: some MachORepresentableWithCache) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return resolversByImageIdentifier[AnyHashable(machO.identifier)] != nil
    }

    public func remove(for machO: some MachORepresentableWithCache) {
        lock.lock()
        defer { lock.unlock() }
        resolversByImageIdentifier[AnyHashable(machO.identifier)] = nil
    }
}
