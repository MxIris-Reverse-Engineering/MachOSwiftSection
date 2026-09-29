import SwiftDeclaration
import MachOFoundation
import MemberwiseInit

@MemberwiseInit(.public)
public struct SwiftDeclarationIndexConfiguration: Hashable, Codable, Sendable {
    public var showCImportedTypes: Bool = false

    /// Where the images this binary links are looked for when a fact has to
    /// be read from one of them: whether a stored field's type is a property
    /// wrapper defined in another image (`PropertyWrapperTypeCatalog`), and
    /// which class a standalone file's bound superclass or category target
    /// is (`ObjCAncestorResolver` — the ObjC ancestor chain behind `override`
    /// and the explicit-selector verdict). The running system's dyld shared
    /// cache covers the OS frameworks; a standalone framework, a simulator
    /// runtime's root or an archived cache is added ahead of it. Cache images
    /// built for none of the binary's platforms are never candidates, so an
    /// iOS binary on a macOS host resolves nothing until its runtime is
    /// named here. An in-process image resolves through the loaded images
    /// and ignores this.
    public var dependencySearchPaths: [DependencySearchPath] = [.systemDyldSharedCache]
}
