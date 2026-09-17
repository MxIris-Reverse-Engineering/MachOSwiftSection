import SwiftDeclaration
import MachOFoundation
import MemberwiseInit

@MemberwiseInit(.public)
public struct SwiftDeclarationIndexConfiguration: Hashable, Codable, Sendable {
    public var showCImportedTypes: Bool = false

    /// Where the images this binary links are looked for when a fact has to
    /// be read from one of them — today, whether a stored field's type is a
    /// property wrapper defined in another image (`PropertyWrapperTypeCatalog`).
    /// The running system's dyld shared cache covers the OS frameworks; a
    /// standalone framework or an archived cache is added ahead of it. An
    /// in-process image resolves through the loaded images and ignores this.
    public var dependencySearchPaths: [DependencySearchPath] = [.systemDyldSharedCache]
}
