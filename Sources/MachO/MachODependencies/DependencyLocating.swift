#if canImport(Darwin)
import Darwin
#endif
import MachOKit
import MachOKitExtensions

/// Turns a dependency load name into a concrete image of the root's reader
/// type — the one seam `DependencyClosure` needs, so the traversal is
/// independent of *where* images come from (the active dyld, a set of search
/// paths, or a test's hand-built table).
public protocol DependencyLocating<MachO> {
    associatedtype MachO: MachORepresentableWithCache

    /// The image `loadName` refers to, or `nil` when this locator cannot find
    /// it. `loadName` is the raw load-command spelling; implementations
    /// normalize it themselves (see `DependencyLoadName.bareImageName(of:)`).
    func locate(loadName: String) -> MachO?
}

/// Resolves dependencies through the active dyld: system frameworks resolve
/// from the shared cache automatically, and locally loaded frameworks resolve
/// as long as they are already mapped into this process.
///
/// Answers from a table of the images dyld had mapped when the locator was
/// made: one pass over them, keeping the first image per bare name — the
/// image `MachOImage(name:)` picks, by the same naming rule — instead of that
/// initializer's own pass per lookup. A closure of a few hundred
/// dependencies, in a process with a thousand images mapped, split the same
/// paths hundreds of thousands of times and kept every other printing task
/// waiting on its catalog meanwhile (evolution proposal
/// `faster-lazy-definition-indexing`). An image mapped after the locator was
/// made is not found by it; a new locator sees it.
public struct InProcessDependencyLocator: DependencyLocating, Sendable {
    /// Per bare name, the first mapped image carrying it — `nil` when dyld
    /// had no header for that image, as `MachOImage(name:)` answers then.
    private let imagesByBareName: [String: MachOImage?]

    public init() {
        var imagesByBareName: [String: MachOImage?] = [:]
        #if canImport(Darwin)
        for index in 0 ..< _dyld_image_count() {
            guard let pathC = _dyld_get_image_name(index) else { continue }
            let bareImageName = DependencyLoadName.bareImageName(of: String(cString: pathC))
            guard imagesByBareName[bareImageName] == nil else { continue }
            imagesByBareName.updateValue(_dyld_get_image_header(index).map { MachOImage(ptr: $0) }, forKey: bareImageName)
        }
        #endif
        self.imagesByBareName = imagesByBareName
    }

    public func locate(loadName: String) -> MachOImage? {
        let bareImageName = DependencyLoadName.bareImageName(of: loadName)
        guard !bareImageName.isEmpty, let image = imagesByBareName[bareImageName] else { return nil }
        return image
    }
}
