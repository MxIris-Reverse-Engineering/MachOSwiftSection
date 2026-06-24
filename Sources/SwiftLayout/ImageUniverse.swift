import MachOSwiftSection

/// The set of images the layout engine may resolve types against, plus the
/// resolution entry point the resolver uses to map a fully-qualified type name
/// to its defining image and descriptor.
///
/// The single-image phase builds this with `singleImage(_:)`. The
/// dependency-closure phase adds a root image plus an ordered list of
/// dependency images.
///
/// Indexing is **lazy**: the root is indexed eagerly (it is the binary being
/// laid out), but each dependency is indexed only when a lookup misses every
/// already-indexed image, advancing through the dependency list in order and
/// stopping as soon as the name resolves. A transitive closure of the OS can
/// run to hundreds of images; eagerly demangling every one's type section would
/// cost seconds, whereas real lookups hit an early Swift dependency and index
/// only a handful. A genuine miss (a name defined nowhere) indexes the whole
/// list once, after which every further lookup is `O(1)`.
///
/// Because the resolver only ever calls `resolveType(byQualifiedTypeName:)` /
/// `resolveProtocolClassConstraint(byQualifiedTypeName:)`, neither it nor any
/// layout bridge changes when the universe grows from one image to a closure.
///
/// **Threading contract.** `ImageUniverse` is declared `@unchecked Sendable` so
/// the rest of the layout pipeline (which transitively holds it through a
/// non-`Sendable` `StaticTypeLayoutResolver` and a `StaticLayoutCalculator`
/// struct) can be carried into a `Sendable` holder. The universe itself is
/// **not internally synchronized**: lazy dependency indexing mutates
/// `nextDependencyToIndex` / `typeIndex` / `protocolIndex` / `objCClassIndex`
/// in place during lookups. Concurrent direct sharing is therefore the
/// holder's responsibility — the in-tree owner that needs cross-task safety,
/// `MachOFileStaticFieldLayoutProvider`, funnels every calculator call through
/// one `NSLock` for exactly this reason (see
/// `SwiftDeclarationRendering/StaticFieldLayoutProvider.swift`). If a future
/// caller needs to share an `ImageUniverse` across tasks without that outer
/// lock, push the synchronization down into this class (or convert the
/// pipeline to an `actor`).
public final class ImageUniverse<MachO: MachOSwiftSectionRepresentableWithCache>: @unchecked Sendable {
    /// The root image (the binary whose types are being laid out). Its
    /// definitions take priority when a name is defined in more than one image.
    public let rootImage: ImageReference<MachO>

    /// The dependency images, in resolution order (breadth-first from the root).
    /// Held un-indexed until a lookup needs them.
    private let dependencyMachOs: [MachO]

    /// Index of the next dependency in `dependencyMachOs` not yet folded into
    /// the merged index. Lookups advance this until they resolve or exhaust it.
    private var nextDependencyToIndex = 0

    /// Closure-wide type index: fully-qualified name → (defining image,
    /// descriptor). Seeded with the root and grown lazily, first writer wins —
    /// so the root and earlier dependencies shadow later ones.
    private var typeIndex: [String: (image: ImageReference<MachO>, descriptor: TypeContextDescriptorWrapper)] = [:]

    /// Closure-wide protocol class-constraint index, grown with the same
    /// root-first / first-writer-wins policy as `typeIndex`.
    private var protocolIndex: [String: (image: ImageReference<MachO>, constraint: ProtocolClassConstraint)] = [:]

    /// Closure-wide Objective-C class start-layout index (bare name →
    /// instanceSize/alignmentMask), grown lazily alongside `typeIndex` with the
    /// same root-first / first-writer-wins policy. Lets a Swift class start its
    /// fields at the size of an ObjC ancestor that lives in another image.
    private var objCClassIndex: [String: (instanceSize: Int, alignmentMask: Int)] = [:]

    init(rootImage: ImageReference<MachO>, dependencyMachOs: [MachO] = []) {
        self.rootImage = rootImage
        self.dependencyMachOs = dependencyMachOs
        mergeIndexes(of: rootImage)
    }

    /// The number of dependency images in the closure (whether or not indexed).
    public var dependencyImageCount: Int { dependencyMachOs.count }

    /// The install paths of the dependency images, in resolution order.
    public var dependencyImagePaths: [String] { dependencyMachOs.map(\.imagePath) }

    /// Builds a single-image universe: types resolve only within `machO`.
    public static func singleImage(_ machO: MachO) throws -> ImageUniverse<MachO> {
        ImageUniverse(rootImage: try ImageReference(machO: machO))
    }

    /// The low-level dependency-closure factory: the caller has already located
    /// every dependency image. Decoupled from any locating strategy (dyld cache,
    /// on-disk search, in-process dyld) so it is trivially testable — the
    /// convenience factories in `ImageUniverse+DependencyClosure.swift` do the
    /// locating and call through here. The root's types take priority;
    /// dependencies resolve in the given order, first writer wins.
    public static func dependencyClosure(root: MachO, dependencyImages: [MachO]) throws -> ImageUniverse<MachO> {
        ImageUniverse(rootImage: try ImageReference(machO: root), dependencyMachOs: dependencyImages)
    }

    /// Resolves a fully-qualified type name to the image that defines it and
    /// its descriptor, or `nil` if no image in the closure defines it.
    func resolveType(
        byQualifiedTypeName qualifiedTypeName: String
    ) -> (image: ImageReference<MachO>, descriptor: TypeContextDescriptorWrapper)? {
        if let resolved = typeIndex[qualifiedTypeName] { return resolved }
        while typeIndex[qualifiedTypeName] == nil, indexNextDependency() {}
        return typeIndex[qualifiedTypeName]
    }

    /// Resolves a fully-qualified protocol name to its class constraint, or
    /// `nil` if no image in the closure defines that protocol. Used to decide
    /// whether an existential is class-bound.
    func resolveProtocolClassConstraint(
        byQualifiedTypeName qualifiedTypeName: String
    ) -> ProtocolClassConstraint? {
        if let resolved = protocolIndex[qualifiedTypeName] { return resolved.constraint }
        while protocolIndex[qualifiedTypeName] == nil, indexNextDependency() {}
        return protocolIndex[qualifiedTypeName]?.constraint
    }

    /// Resolves an Objective-C class's start layout (its instance size and a
    /// pointer start alignment) by bare name, or `nil` if no image in the
    /// closure defines that ObjC class. The third resolution seam, sharing the
    /// same lazy fold-in as `resolveType` / `resolveProtocolClassConstraint`:
    /// every dependency's ObjC index is merged when that dependency is folded,
    /// so this needs no extra scan over the closure.
    func resolveObjCClassInstanceSize(
        byBareName bareName: String
    ) -> (instanceSize: Int, alignmentMask: Int)? {
        if let resolved = objCClassIndex[bareName] { return resolved }
        while objCClassIndex[bareName] == nil, indexNextDependency() {}
        return objCClassIndex[bareName]
    }

    /// Folds the next un-indexed dependency into the merged indexes. Returns
    /// `false` when the dependency list is exhausted. A dependency whose
    /// `ImageReference` cannot be built (a malformed binary) is skipped rather
    /// than failing the closure.
    private func indexNextDependency() -> Bool {
        guard nextDependencyToIndex < dependencyMachOs.count else { return false }
        let machO = dependencyMachOs[nextDependencyToIndex]
        nextDependencyToIndex += 1
        if let reference = try? ImageReference(machO: machO) {
            mergeIndexes(of: reference)
        }
        return true
    }

    /// Merges one image's per-image indexes into the closure-wide indexes,
    /// first writer wins (so already-indexed images shadow this one).
    private func mergeIndexes(of image: ImageReference<MachO>) {
        for (qualifiedTypeName, descriptor) in image.typeDescriptorsByQualifiedName where typeIndex[qualifiedTypeName] == nil {
            typeIndex[qualifiedTypeName] = (image, descriptor)
        }
        for (qualifiedTypeName, classConstraint) in image.protocolClassConstraintsByQualifiedName where protocolIndex[qualifiedTypeName] == nil {
            protocolIndex[qualifiedTypeName] = (image, classConstraint)
        }
        for (bareName, startLayout) in image.objCClassInstanceSizesByBareName where objCClassIndex[bareName] == nil {
            objCClassIndex[bareName] = startLayout
        }
    }
}
