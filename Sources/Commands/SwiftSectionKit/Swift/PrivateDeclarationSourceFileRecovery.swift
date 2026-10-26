import MachOKit
@_spi(Support) import SwiftIndexing
@_spi(Support) import SwiftPrivateDiscriminators

/// What `dump` and `interface` share to name the source files of an image's
/// private declarations (evolution proposal
/// `private-declaration-source-files`).
enum PrivateDeclarationSourceFileRecovery {
    /// Said before the search, which is what keeps a large framework silent
    /// for a while before its first declaration.
    static let progressMessage = "Recovering the source files of private declarations..."

    /// The index of `indexer`'s image, every discriminator the image declares
    /// something with already searched for: printing then asks for each
    /// declaration's, and every answer is a lookup.
    static func index(searchingEveryDeclarationOf indexer: SwiftDeclarationIndexer<MachOFile>) -> PrivateDiscriminatorSourceFileIndex {
        let index = PrivateDiscriminatorSourceFileIndex(indexer: indexer)
        index.recoverSourceFiles(ofEveryDeclarationIn: indexer)
        return index
    }
}
