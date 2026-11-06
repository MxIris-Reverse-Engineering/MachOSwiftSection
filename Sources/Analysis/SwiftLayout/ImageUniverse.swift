import MachOSwiftSection
import MachOFoundation

/// The set of images the layout engine may resolve types against, plus the
/// resolution entry point the resolver uses to map a fully-qualified type name
/// to its defining image and descriptor.
///
/// The single-image phase builds this with `singleImage(_:)`. The
/// dependency-closure phase adds a root image plus an ordered list of
/// dependency images.
///
/// Indexing is **lazy**, per kind of lookup: a type lookup folds images —
/// the root first, then the dependencies in order — into the type index only,
/// stopping as soon as the name resolves; protocol, Objective-C class and
/// associated-type witness lookups fold into their own indexes the same way.
/// A transitive closure of the OS can run to hundreds of images; eagerly
/// demangling every one's type section would cost seconds, whereas real
/// lookups hit an early Swift dependency and index only a handful. A genuine
/// miss (a name defined nowhere) folds the whole list once for that kind,
/// after which every further lookup of the kind is `O(1)`. Each image's
/// indexes come from `ImageReference.shared(for:)`, so every universe that
/// folds an image in reuses what another already built.
///
/// Because the resolver only ever calls `resolveType(byQualifiedTypeName:)` /
/// `resolveProtocol(byQualifiedTypeName:)` and the other `resolve…` seams,
/// neither it nor any layout bridge changes when the universe grows from one
/// image to a closure.
///
/// **Threading contract.** `ImageUniverse` is declared `@unchecked Sendable` so
/// the rest of the layout pipeline (which transitively holds it through a
/// non-`Sendable` `StaticTypeLayoutResolver` and a `StaticLayoutCalculator`
/// struct) can be carried into a `Sendable` holder. The universe itself is
/// **not internally synchronized**: lazy dependency indexing mutates
/// `foldedImageCountByIndexKind` / `dependencyImages` / `typeIndex` / `protocolIndex` / `objCClassIndex`
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

    /// The dependencies' references, made when a lookup of any kind first
    /// reaches the dependency; `nil` until then.
    private var dependencyImages: [ImageReference<MachO>?]

    /// The kinds of lookup, each folding images into its own indexes.
    ///
    /// A type lookup used to fold every index of each dependency it passed,
    /// so the one pass that resolved a field type also read the protocol
    /// lists, Objective-C classes and associated-type records of every image
    /// on the way (evolution proposal `machofile-performance`). The images a
    /// kind folds, and the order it folds them in, are the same as before, so
    /// each lookup answers what it did.
    enum IndexKind: CaseIterable {
        case types
        /// The Swift protocols' class constraints together with the
        /// Swift-declared `@objc` protocols, which a protocol lookup asks in
        /// that order of each image as it folds it in.
        case protocols
        case objCClasses
        case associatedTypeWitnesses
    }

    /// How many images — the root first, then the dependencies in order —
    /// each kind of lookup has folded into its indexes. Lookups advance
    /// their kind's count until they resolve or exhaust the images.
    private var foldedImageCountByIndexKind: [IndexKind: Int] = [:]

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

    /// Closure-wide associated-type witness index: `"conforming|protocol|assoc"`
    /// → (defining image, witness record). Grown lazily with the same root-first
    /// / first-writer-wins policy. Lets a `dependentMemberType` resolve its
    /// witness against whichever image declares the conformance.
    private var associatedTypeWitnessIndex: [String: (image: ImageReference<MachO>, record: AssociatedTypeRecord)] = [:]

    /// Closure-wide Swift-declared `@objc` protocol index (Swift qualified
    /// names parsed from `__objc_protolist`), grown lazily alongside the other
    /// indexes. Membership is the whole answer — an `@objc` protocol is always
    /// class-bound and carries no Swift witness table.
    private var objCProtocolQualifiedNames: Set<String> = []

    init(rootImage: ImageReference<MachO>, dependencyMachOs: [MachO] = []) {
        self.rootImage = rootImage
        self.dependencyMachOs = dependencyMachOs
        self.dependencyImages = Array(repeating: nil, count: dependencyMachOs.count)
    }

    /// The number of dependency images in the closure (whether or not indexed).
    public var dependencyImageCount: Int { dependencyMachOs.count }

    /// How many dependency images lookups have folded in so far, a malformed
    /// one that indexed nothing included: the most any kind of lookup has
    /// reached.
    var indexedDependencyImageCount: Int {
        max(0, (foldedImageCountByIndexKind.values.max() ?? 0) - 1)
    }

    /// The install paths of the dependency images, in resolution order.
    public var dependencyImagePaths: [String] { dependencyMachOs.map(\.imagePath) }

    /// Builds a single-image universe: types resolve only within `machO`.
    public static func singleImage(_ machO: MachO) throws -> ImageUniverse<MachO> {
        ImageUniverse(rootImage: ImageReference.shared(for: machO))
    }

    /// The low-level dependency-closure factory: the caller has already located
    /// every dependency image. Decoupled from any locating strategy (dyld cache,
    /// on-disk search, in-process dyld) so it is trivially testable — the
    /// convenience factories in `ImageUniverse+DependencyClosure.swift` do the
    /// locating and call through here. The root's types take priority;
    /// dependencies resolve in the given order, first writer wins.
    public static func dependencyClosure(root: MachO, dependencyImages: [MachO]) throws -> ImageUniverse<MachO> {
        ImageUniverse(rootImage: ImageReference.shared(for: root), dependencyMachOs: dependencyImages)
    }

    /// Resolves a fully-qualified type name to the image that defines it and
    /// its descriptor, or `nil` if no image in the closure defines it.
    func resolveType(
        byQualifiedTypeName qualifiedTypeName: String
    ) -> (image: ImageReference<MachO>, descriptor: TypeContextDescriptorWrapper)? {
        if let resolved = typeIndex[qualifiedTypeName] { return resolved }
        while typeIndex[qualifiedTypeName] == nil, foldNextImage(into: .types) {}
        return typeIndex[qualifiedTypeName]
    }

    /// What a protocol name resolves to: a Swift protocol descriptor, or only
    /// an Objective-C protocol record.
    enum ResolvedProtocol: Equatable {
        /// A Swift protocol, with the class constraint its descriptor declares.
        case swift(ProtocolClassConstraint)
        /// A Swift-declared `@objc` protocol, which gets no Swift protocol
        /// descriptor — its only runtime artifact is the Objective-C protocol
        /// record. Always class-bound, and it contributes no witness table.
        case objC
    }

    /// Resolves a fully-qualified protocol name, or returns `nil` if no image
    /// in the closure declares that protocol. Used to decide whether an
    /// existential or a generic parameter is class-bound.
    ///
    /// Both records are looked for in each image as it is folded in, so a name
    /// resolves in the first image that knows it either way. Asked of the Swift
    /// descriptors alone first, a Swift-declared `@objc` protocol — which has
    /// none — folded in the whole closure before its record, which the root
    /// usually holds a copy of, was looked at: one field of Dock's DockHelper
    /// indexed the 500-odd images its closure reaches in the system's cache.
    func resolveProtocol(byQualifiedTypeName qualifiedTypeName: String) -> ResolvedProtocol? {
        if let resolved = indexedProtocol(byQualifiedTypeName: qualifiedTypeName) { return resolved }
        while foldNextImage(into: .protocols) {
            if let resolved = indexedProtocol(byQualifiedTypeName: qualifiedTypeName) { return resolved }
        }
        return nil
    }

    /// What the images folded in so far say a protocol name is. A Swift
    /// protocol descriptor wins over an Objective-C record of the same name,
    /// the order the two were asked in before one lookup asked both.
    private func indexedProtocol(byQualifiedTypeName qualifiedTypeName: String) -> ResolvedProtocol? {
        if let resolved = protocolIndex[qualifiedTypeName] { return .swift(resolved.constraint) }
        if objCProtocolQualifiedNames.contains(qualifiedTypeName) { return .objC }
        return nil
    }

    /// Resolves an Objective-C class's start layout (its instance size and a
    /// pointer start alignment) by bare name, or `nil` if no image in the
    /// closure defines that ObjC class. The third resolution seam, with the
    /// same lazy fold-in as `resolveType` / `resolveProtocol`.
    func resolveObjCClassInstanceSize(
        byBareName bareName: String
    ) -> (instanceSize: Int, alignmentMask: Int)? {
        if let resolved = objCClassIndex[bareName] { return resolved }
        while objCClassIndex[bareName] == nil, foldNextImage(into: .objCClasses) {}
        return objCClassIndex[bareName]
    }

    /// Resolves an associated-type witness — the concrete type a conformance
    /// binds an associated type to — to its defining image and record, or `nil`
    /// if no image in the closure declares that conformance. The fourth
    /// resolution seam, sharing the same lazy fold-in as the others.
    func resolveAssociatedTypeWitness(
        forKey key: String
    ) -> (image: ImageReference<MachO>, record: AssociatedTypeRecord)? {
        if let resolved = associatedTypeWitnessIndex[key] { return resolved }
        while associatedTypeWitnessIndex[key] == nil, foldNextImage(into: .associatedTypeWitnesses) {}
        return associatedTypeWitnessIndex[key]
    }

    /// Resolves the witness a conformance of `conformingName` to
    /// `protocolName` binds `associatedTypeName` to, or `nil` if no image in
    /// the closure records that conformance.
    ///
    /// The stand-in for an unbound class-bound generic parameter
    /// (`GenericArgumentEnvironment.classBoundParameterPlaceholderQualifiedName`)
    /// is answered without a lookup: no image records a conformance of it, and
    /// asking folded every image of the closure into the witness index before
    /// answering `nil` — all 552 of SwiftUI's, for one member of a class-bound
    /// parameter (evolution proposal `machofile-performance`).
    func resolveAssociatedTypeWitness(
        conformingName: String,
        protocolName: String,
        associatedTypeName: String
    ) -> (image: ImageReference<MachO>, record: AssociatedTypeRecord)? {
        guard conformingName != GenericArgumentEnvironment.classBoundParameterPlaceholderQualifiedName else { return nil }
        return resolveAssociatedTypeWitness(forKey: ImageReference<MachO>.associatedTypeWitnessKey(
            conformingName: conformingName,
            protocolName: protocolName,
            associatedTypeName: associatedTypeName
        ))
    }

    /// Folds the next image `kind` has not reached — the root first, then the
    /// dependencies in order — into that kind's closure-wide indexes, first
    /// writer wins (so already-folded images shadow this one). Returns `false`
    /// when every image is folded.
    private func foldNextImage(into kind: IndexKind) -> Bool {
        let foldedImageCount = foldedImageCountByIndexKind[kind, default: 0]
        guard foldedImageCount <= dependencyMachOs.count else { return false }
        foldedImageCountByIndexKind[kind] = foldedImageCount + 1
        guard let image = image(atResolutionPosition: foldedImageCount) else { return true }
        switch kind {
        case .types:
            for (qualifiedTypeName, descriptor) in image.typeDescriptorsByQualifiedName where typeIndex[qualifiedTypeName] == nil {
                typeIndex[qualifiedTypeName] = (image, descriptor)
            }
        case .protocols:
            for (qualifiedTypeName, classConstraint) in image.protocolClassConstraintsByQualifiedName where protocolIndex[qualifiedTypeName] == nil {
                protocolIndex[qualifiedTypeName] = (image, classConstraint)
            }
            objCProtocolQualifiedNames.formUnion(image.objCProtocolQualifiedNames)
        case .objCClasses:
            for (bareName, startLayout) in image.objCClassInstanceSizesByBareName where objCClassIndex[bareName] == nil {
                objCClassIndex[bareName] = startLayout
            }
        case .associatedTypeWitnesses:
            for (key, record) in image.associatedTypeWitnessRecordsByKey where associatedTypeWitnessIndex[key] == nil {
                associatedTypeWitnessIndex[key] = (image, record)
            }
        }
        return true
    }

    /// The image at `position` in resolution order: the root at 0, then the
    /// dependencies. A dependency's reference is made on first use and kept
    /// for every kind; one that cannot be made (a malformed binary) is
    /// skipped rather than failing the closure.
    private func image(atResolutionPosition position: Int) -> ImageReference<MachO>? {
        guard position > 0 else { return rootImage }
        let dependencyIndex = position - 1
        if let dependencyImage = dependencyImages[dependencyIndex] {
            return dependencyImage
        }
        let dependencyImage = ImageReference.shared(for: dependencyMachOs[dependencyIndex])
        dependencyImages[dependencyIndex] = dependencyImage
        return dependencyImage
    }
}

extension ImageUniverse {
    /// How many images — the root included — lookups of `kind` have folded
    /// in, for tests watching which lookups fold what.
    func foldedImageCount(for kind: IndexKind) -> Int {
        foldedImageCountByIndexKind[kind, default: 0]
    }
}
