import MachOKit
import MachOKitExtensions

/// How far a `DependencyClosure` follows the load commands.
public enum DependencyTraversal: Sendable, Hashable {
    /// Only the root's own `LC_LOAD_DYLIB`-family entries.
    case direct
    /// The root's dependencies, their dependencies, and so on — breadth-first.
    case transitive
}

/// The dependency images of a root binary, resolved through a
/// `DependencyLocating` strategy.
///
/// `images` is in **resolution order**: the load-command order for a direct
/// traversal, breadth-first for a transitive one (the root's direct
/// dependencies first, then theirs, …). The order is part of the contract, not
/// an implementation detail — a consumer that indexes dependencies lazily
/// (`SwiftLayout.ImageUniverse`) folds them in this order and stops at the
/// first hit, and depth-first would put Foundation's whole subtree ahead of the
/// root's own second Swift dependency.
///
/// Images are deduplicated twice: by bare image name (`DependencyLoadName`),
/// never by load-name spelling, and by image identity
/// (`MachORepresentableWithCache.identifier`, `LC_UUID`-keyed for a file) —
/// the file locator registers an explicit file under its on-disk path, its
/// install name and its bare name, so a root that links the same binary under
/// two load names reaches one image twice, and it is collected once. The root
/// itself is excluded. A dependency the locator cannot find is not an error:
/// its load name is recorded in `unresolvedLoadNames` and traversal
/// continues, so the result degrades per dependency rather than failing
/// whole.
public struct DependencyClosure<MachO: MachORepresentableWithCache>: Sendable {
    public let root: MachO
    public let traversal: DependencyTraversal
    /// The resolved dependency images in resolution order (see the type
    /// documentation), root excluded.
    public let images: [MachO]
    /// Load names no locator could resolve, in encounter order, deduplicated by
    /// bare image name.
    public let unresolvedLoadNames: [String]
    /// Search paths the file locator could not open (always empty for a locator
    /// that has no search paths, such as the in-process one).
    public let searchPathLoadFailures: [DependencySearchPathLoadFailure]

    /// Resolves the closure of `root` through `locator`. The general entry
    /// point; the reader-specific initializers below pick the locator.
    public init(root: MachO, traversal: DependencyTraversal = .transitive, locator: some DependencyLocating<MachO>) {
        self.init(root: root, traversal: traversal, locator: locator, searchPathLoadFailures: [])
    }

    init(root: MachO, traversal: DependencyTraversal, locator: some DependencyLocating<MachO>, searchPathLoadFailures: [DependencySearchPathLoadFailure]) {
        var visitedBareImageNames: Set<String> = [DependencyLoadName.bareImageName(of: root.imagePath)]
        var collectedImageIdentifiers: Set<MachO.Identifier> = [root.identifier]
        var images: [MachO] = []
        var unresolvedLoadNames: [String] = []
        var frontier: [MachO] = [root]

        while !frontier.isEmpty {
            var nextFrontier: [MachO] = []
            for image in frontier {
                for loadName in image.dependencies.map(\.dylib.name) {
                    let bareImageName = DependencyLoadName.bareImageName(of: loadName)
                    guard !bareImageName.isEmpty, visitedBareImageNames.insert(bareImageName).inserted else { continue }
                    guard let dependencyImage = locator.locate(loadName: loadName) else {
                        unresolvedLoadNames.append(loadName)
                        continue
                    }
                    // Resolved, but to an image already collected under another
                    // spelling: nothing to add, and nothing to report.
                    guard collectedImageIdentifiers.insert(dependencyImage.identifier).inserted else { continue }
                    images.append(dependencyImage)
                    nextFrontier.append(dependencyImage)
                }
            }
            frontier = traversal == .transitive ? nextFrontier : []
        }

        self.root = root
        self.traversal = traversal
        self.images = images
        self.unresolvedLoadNames = unresolvedLoadNames
        self.searchPathLoadFailures = searchPathLoadFailures
    }
}

// MARK: - In-process (MachOImage)

extension DependencyClosure where MachO == MachOImage {
    /// Resolves an in-process image's dependencies through the active dyld
    /// (`InProcessDependencyLocator`).
    public init(root: MachOImage, traversal: DependencyTraversal = .transitive) {
        self.init(root: root, traversal: traversal, locator: InProcessDependencyLocator())
    }
}

// MARK: - Offline (MachOFile)

extension DependencyClosure where MachO == MachOFile {
    /// Resolves a file-backed image's dependencies through `searchPaths`
    /// (`FileDependencyLocator`). Fat explicit files contribute the slice
    /// matching the root's architecture.
    public init(root: MachOFile, searchPaths: [DependencySearchPath] = [.systemDyldSharedCache], traversal: DependencyTraversal = .transitive) {
        let locator = FileDependencyLocator(searchPaths: searchPaths, preferredCPU: root.header.cpu)
        self.init(root: root, traversal: traversal, locator: locator, searchPathLoadFailures: locator.loadFailures)
    }
}
