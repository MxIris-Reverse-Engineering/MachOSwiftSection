import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Core) import MachOObjCSection
@_spi(Internals) import Demangling
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
import SwiftInspection

/// The source files of an image's private discriminators, recovered on
/// demand and remembered (evolution proposal `private-declarations`).
///
/// The candidates come from the image itself: the names of every Swift type,
/// protocol and extension its indexer holds, with the private declarations
/// each reads, and the names of its Objective-C classes and protocols. They
/// are read on the first request, and every answer is kept — a discriminator
/// nothing recovers too, which is the slowest one to search for — so asking
/// again costs a lookup. A host keeps one per image and drops it with the
/// image.
///
/// `@unchecked Sendable`: the candidates and answers are only read and
/// written under `lock`. The image's names are read outside it, on a large
/// stack: reading them prints every name the image declares, and nothing
/// demangles under a lock. Two first requests that overlap therefore both
/// read them, and the one that comes back second drops what it read. The
/// search runs under the lock, so two requests for one image still search
/// once. Once the candidates are built, the names closure is let go of, and
/// with it what it captured — an indexer, and through it the image's caches.
public final class PrivateDiscriminatorSourceFileIndex: @unchecked Sendable {
    private enum Answer {
        case recovered(PrivateDiscriminatorSourceFiles.SourceFile)
        case unrecovered
    }

    private let imagePath: String

    private let knownFileNames: [String]

    private let lock = NSLock()

    /// Reads the image's names; `nil` once the candidates are built.
    private var imageNames: (@Sendable () -> [PrivateDiscriminatorSourceFiles.ImageName])?

    private var candidates: PrivateDiscriminatorSourceFiles.Candidates?

    private var answerByDiscriminator: [String: Answer] = [:]

    private var numberOfSearches = 0

    /// How many searches have run: one for each request that brought a
    /// discriminator not asked for before. Read by the tests.
    var searchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return numberOfSearches
    }

    /// - Parameters:
    ///   - imagePath: The image the names come from. Its file name is the
    ///     first module name tried.
    ///   - knownFileNames: File names to try before any is derived from the
    ///     image's names.
    ///   - imageNames: Every name the image declares. Called on the first
    ///     request — by each of two first requests that overlap — on a large
    ///     stack and outside the index's lock, and let go of once the
    ///     candidates are built.
    public init(
        imagePath: String,
        knownFileNames: [String] = PrivateDiscriminatorSourceFiles.knownFileNames,
        imageNames: @escaping @Sendable () -> [PrivateDiscriminatorSourceFiles.ImageName]
    ) {
        self.imagePath = imagePath
        self.knownFileNames = knownFileNames
        self.imageNames = imageNames
    }

    /// The image of a prepared indexer, loaded into this process. The index
    /// holds the indexer until it has read the names.
    @_spi(Support)
    public convenience init(indexer: SwiftDeclarationIndexer<MachOImage>, knownFileNames: [String] = PrivateDiscriminatorSourceFiles.knownFileNames) {
        self.init(imagePath: indexer.machO.imagePath, knownFileNames: knownFileNames) {
            Self.swiftNames(in: indexer) + Self.objectiveCNames(in: indexer.machO)
        }
    }

    /// The image of a prepared indexer, read from a file or a dyld shared
    /// cache. The index holds the indexer until it has read the names.
    @_spi(Support)
    public convenience init(indexer: SwiftDeclarationIndexer<MachOFile>, knownFileNames: [String] = PrivateDiscriminatorSourceFiles.knownFileNames) {
        self.init(imagePath: indexer.machO.imagePath, knownFileNames: knownFileNames) {
            Self.swiftNames(in: indexer) + Self.objectiveCNames(in: indexer.machO)
        }
    }

    /// The source file of each of `discriminators` that a candidate
    /// produces; a discriminator none does is left out.
    ///
    /// Only the discriminators not asked for before are searched for. A
    /// search costs one hash per candidate and module name, and one for a
    /// discriminator nothing recovers runs through every candidate: in a
    /// debug build that is seconds for SwiftUI. Ask for the ones shown.
    public func sourceFiles(forDiscriminators discriminators: some Sequence<String>) -> [String: PrivateDiscriminatorSourceFiles.SourceFile] {
        let requestedDiscriminators = Set(discriminators)
        // Read outside the lock and on a large stack: reading the names
        // prints every one of them, and the request may come from a
        // cooperative thread's 512 KB stack. One hop for the whole batch;
        // a thread that already has the stack reads them where it is.
        let readCandidates = imageNamesToRead(forDiscriminators: requestedDiscriminators).map { imageNames in
            PrivateDiscriminatorSourceFiles.Candidates(imagePath: imagePath, imageNames: StackSafeExecutor.withLargeStack { imageNames() })
        }
        lock.lock()
        defer { lock.unlock() }
        // Another first request may have built them meanwhile: those stay,
        // and these are dropped.
        if candidates == nil, let readCandidates {
            candidates = readCandidates
            imageNames = nil
        }
        let unansweredDiscriminators = requestedDiscriminators.filter { answerByDiscriminator[$0] == nil }
        if !unansweredDiscriminators.isEmpty, let candidates {
            numberOfSearches += 1
            let search = PrivateDiscriminatorSourceFiles(recovering: unansweredDiscriminators, candidates: candidates, knownFileNames: knownFileNames)
            // A search also finds the file a synthesized one was made for.
            for (discriminator, sourceFile) in search.sourceFileByDiscriminator {
                answerByDiscriminator[discriminator] = .recovered(sourceFile)
            }
            for discriminator in unansweredDiscriminators where answerByDiscriminator[discriminator] == nil {
                answerByDiscriminator[discriminator] = .unrecovered
            }
        }
        var sourceFileByDiscriminator: [String: PrivateDiscriminatorSourceFiles.SourceFile] = [:]
        for discriminator in requestedDiscriminators {
            if case .recovered(let sourceFile) = answerByDiscriminator[discriminator] {
                sourceFileByDiscriminator[discriminator] = sourceFile
            }
        }
        return sourceFileByDiscriminator
    }

    /// What reads the image's names, when a request for `discriminators`
    /// brings one not answered before and the candidates are not built yet.
    private func imageNamesToRead(forDiscriminators discriminators: Set<String>) -> (@Sendable () -> [PrivateDiscriminatorSourceFiles.ImageName])? {
        lock.lock()
        defer { lock.unlock() }
        guard candidates == nil, discriminators.contains(where: { answerByDiscriminator[$0] == nil }) else { return nil }
        return imageNames
    }

    // MARK: - Names of the Image

    /// The names of every Swift type, protocol and extension `indexer`
    /// holds, as a reader is shown them, each with the private declarations
    /// it reads.
    private static func swiftNames<MachO>(in indexer: SwiftDeclarationIndexer<MachO>) -> [PrivateDiscriminatorSourceFiles.ImageName] {
        var imageNames: [PrivateDiscriminatorSourceFiles.ImageName] = []
        func append(_ definitionName: some DefinitionName) {
            imageNames.append(.init(printedName: definitionName.name, discriminators: definitionName.node.privateDeclarations.map(\.discriminator)))
        }
        indexer.allTypeDefinitions.keys.forEach(append)
        indexer.allProtocolDefinitions.keys.forEach(append)
        for extensionDefinitions in [indexer.typeExtensionDefinitions, indexer.protocolExtensionDefinitions, indexer.typeAliasExtensionDefinitions, indexer.conformanceExtensionDefinitions] {
            extensionDefinitions.keys.forEach(append)
        }
        return imageNames
    }

    /// The names of the Objective-C classes and protocols an in-process image
    /// declares. A class dyld has realized keeps its read-only data behind
    /// its read-write data.
    private static func objectiveCNames(in machO: MachOImage) -> [PrivateDiscriminatorSourceFiles.ImageName] {
        var names: [String] = []
        for objectiveCClass in machO.objc.classes64 ?? [] {
            let readOnlyData = objectiveCClass.classROData(in: machO)
                ?? objectiveCClass.classRWData(in: machO).flatMap { $0.classROData(in: machO) ?? $0.ext(in: machO)?.classROData(in: machO) }
            if let name = readOnlyData?.name(in: machO) {
                names.append(name)
            }
        }
        for objectiveCProtocol in machO.objc.protocols64 ?? [] {
            names.append(objectiveCProtocol.mangledName(in: machO))
        }
        return objectiveCImageNames(names)
    }

    /// The names of the Objective-C classes and protocols an image read from
    /// a file or a dyld shared cache declares.
    private static func objectiveCNames(in machO: MachOFile) -> [PrivateDiscriminatorSourceFiles.ImageName] {
        var names: [String] = []
        for objectiveCClass in machO.objc.classes64 ?? [] {
            if let name = objectiveCClass.classROData(in: machO)?.name(in: machO) {
                names.append(name)
            }
        }
        for objectiveCProtocol in machO.objc.protocols64 ?? [] {
            names.append(objectiveCProtocol.mangledName(in: machO))
        }
        return objectiveCImageNames(names)
    }

    /// A Swift class or protocol is listed under its mangled runtime name,
    /// `_TtC7SwiftUI…`; the Swift names cover it already.
    private static func objectiveCImageNames(_ names: [String]) -> [PrivateDiscriminatorSourceFiles.ImageName] {
        names.filter { !$0.isEmpty && !$0.hasPrefix("_Tt") }.map { .init(printedName: $0) }
    }
}
