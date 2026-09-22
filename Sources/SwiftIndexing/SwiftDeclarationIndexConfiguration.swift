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

    /// Whether an overriding ObjC method that neither evidence tier could tie
    /// to a Swift member — its IMP carries no `To` thunk symbol and its code
    /// references no Swift symbol, because the optimizer inlined the body
    /// into the thunk (`viewDidHide`, `encodeWithCoder:` in an OS framework)
    /// — is attributed to the ONE member of the class whose name is the
    /// importer's spelling of its selector, so the member prints `override`.
    /// Name evidence only, hence off by default; installed per image as
    /// `ObjCMemberRecoveryOptions` when the indexer prepares. Never touches
    /// a method no ancestor implements, so it cannot add `@objc(name)`.
    public var infersObjCOverridesFromSelectorNames: Bool = false
}
