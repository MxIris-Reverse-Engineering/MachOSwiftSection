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
public struct InProcessDependencyLocator: DependencyLocating, Sendable {
    public init() {}

    public func locate(loadName: String) -> MachOImage? {
        let bareImageName = DependencyLoadName.bareImageName(of: loadName)
        guard !bareImageName.isEmpty else { return nil }
        return MachOImage(name: bareImageName)
    }
}
