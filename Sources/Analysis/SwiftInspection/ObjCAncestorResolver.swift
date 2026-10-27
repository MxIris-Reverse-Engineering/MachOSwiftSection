import Foundation
import FoundationToolbox
import MachOKit
import MachOKitExtensions
import MachOFoundation
@_spi(Internals) import MachOCaches
@_spi(Internals) import MachOSymbols
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
    /// are all real — only the category fold and a class without a class
    /// object, whose superclass only has a name, read those).
    enum DependencyImages {
        case files([MachOFile])
        case loaded([MachOImage])
    }

    private let makeDependencyImages: @Sendable () -> DependencyImages
    private let lock = NSLock()
    private var dependencyImages: DependencyImages?
    private var memoizedClassObjectsByRuntimeName: [String: (any ObjCImplementationClassReading, ObjCClass64)?] = [:]
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
    /// from those images' `__objc_catlist` like a file's. A Swift class
    /// without a class object has no superclass pointer to follow at all —
    /// its descriptor only names the superclass — so names are looked up in
    /// the loaded images the way a file's binds are in its closure.
    public convenience init(inProcessRoot: MachOImage) {
        self.init(loadedImages: { DependencyClosure(root: inProcessRoot, traversal: .transitive).images })
    }

    init(loadedImages: @escaping @Sendable () -> [MachOImage]) {
        self.makeDependencyImages = { .loaded(loadedImages()) }
    }

    /// A resolver over no images: every bind stays unresolvable, exactly the
    /// behavior of a reader with no dependency closure at hand.
    public static let empty = ObjCAncestorResolver(dependencyImages: { [] })

    /// The class object named `runtimeName` and the file defining it, or
    /// `nil` when no dependency file exports such a class — the file-typed
    /// form of `resolvedClassObject(named:)`.
    package func classObject(named runtimeName: String) -> (MachOFile, ObjCClass64)? {
        guard let (reader, classObject) = resolvedClassObject(named: runtimeName), let machOFile = reader.asMachOFile else { return nil }
        return (machOFile, classObject)
    }

    /// The class object named `runtimeName` and the image defining it — a
    /// file of the closure, or an image the process loaded — or `nil` when no
    /// dependency image exports such a class.
    func resolvedClassObject(named runtimeName: String) -> (any ObjCImplementationClassReading, ObjCClass64)? {
        lock.lock()
        defer { lock.unlock() }
        if let memoized = memoizedClassObjectsByRuntimeName[runtimeName] {
            return memoized
        }
        if dependencyImages == nil {
            dependencyImages = makeDependencyImages()
        }
        let exportedName = "_OBJC_CLASS_$_" + runtimeName
        let found: (any ObjCImplementationClassReading, ObjCClass64)? = switch dependencyImages {
        case .files(let files): Self.firstClassObject(named: runtimeName, in: files) { $0.exportTrie?.search(by: exportedName) != nil }
        case .loaded(let images): Self.firstClassObject(named: runtimeName, in: images) { $0.exportTrie?.search(by: exportedName) != nil }
        case nil: nil
        }
        if found == nil {
            #log(.info, "no dependency image defines the ObjC class \(runtimeName, privacy: .public); the chain stops there")
        }
        memoizedClassObjectsByRuntimeName[runtimeName] = .some(found)
        return found
    }

    /// The first of `images` whose class list holds `runtimeName`, among the
    /// ones that export it — an exact pre-check that spares the class-list
    /// read of every image not carrying the class.
    private static func firstClassObject<Image: ObjCImplementationClassReading>(named runtimeName: String, in images: [Image], exportsTheClass: (Image) -> Bool) -> (any ObjCImplementationClassReading, ObjCClass64)? {
        for image in images {
            // A re-export entry (an umbrella framework's) passes here and
            // misses the class list; the defining image follows in the closure.
            guard exportsTheClass(image) else { continue }
            guard let classObject = ObjCClassMethodIndex.shared.storage(in: image)?.classObjectsByRuntimeName[runtimeName] else { continue }
            return (image, classObject)
        }
        return nil
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

    private let cache = SharedCache<ObjCAncestorResolver>(evictionGroup: .objcAncestorResolver, follows: [.symbolStore])

    private init() {}

    /// Installs `resolver` for `machO`, replacing any earlier registration —
    /// a default one a lookup created before it included.
    public func register(_ resolver: ObjCAncestorResolver, for machO: some MachORepresentableWithCache) {
        cache.register(resolver, for: machO)
    }

    /// A file's resolver: the registered one, else a default over the
    /// running system's dyld shared cache, created on first use. The default
    /// is built outside the cache's lock, and concurrent first lookups for
    /// one file share a single build.
    public func resolver(for machOFile: MachOFile) -> ObjCAncestorResolver {
        cache.storage(in: machOFile) { ObjCAncestorResolver(root: $0, searchPaths: [.systemDyldSharedCache]) }
            ?? ObjCAncestorResolver(root: machOFile, searchPaths: [.systemDyldSharedCache])
    }

    /// An in-process image's resolver: the registered one, else a default
    /// over the loaded images, created on first use — consulted for the
    /// category fold only, never for a bind.
    public func resolver(for machOImage: MachOImage) -> ObjCAncestorResolver {
        cache.storage(in: machOImage) { ObjCAncestorResolver(inProcessRoot: $0) }
            ?? ObjCAncestorResolver(inProcessRoot: machOImage)
    }

    /// The resolver for whichever reader kind `machO` reads through — itself,
    /// or the reader beneath its wrappers; `nil` for a reader of another kind.
    /// (Named apart from ``resolver(for:)`` on purpose — a same-labelled
    /// generic overload resolved to itself from inside the cast and recursed.)
    func resolver(forImage machO: some MachORepresentableWithCache) -> ObjCAncestorResolver? {
        if let machOFile = machO.asMachOFile {
            let fileResolver: ObjCAncestorResolver = resolver(for: machOFile)
            return fileResolver
        }
        if let machOImage = machO.asMachOImage {
            let imageResolver: ObjCAncestorResolver = resolver(for: machOImage)
            return imageResolver
        }
        return nil
    }

    public func contains(in machO: some MachORepresentableWithCache) -> Bool {
        cache.contains(in: machO)
    }

    public func remove(for machO: some MachORepresentableWithCache) {
        cache.remove(for: machO)
    }
}
