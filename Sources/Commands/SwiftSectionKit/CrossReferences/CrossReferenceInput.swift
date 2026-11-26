import Foundation
import MachOKit
import MachOKitExtensions
import CrossReferenceAnalysis

/// The images a cross-reference request analyzes: every image of a dyld
/// shared cache, or a set of standalone files read together, as dyld would
/// load them — an app's executable and the frameworks it embeds.
///
/// Addresses in and out are unslid: the cache's own, or each file's own.
public enum CrossReferenceInput: Sendable, Hashable {
    /// Standalone Mach-O files. `architecture` picks a fat binary's slice,
    /// and a fat binary needs one: only arm64 slices can be analyzed.
    case files(paths: [String], architecture: Architecture?)
    /// Every image of the dyld shared cache at `path`.
    case dyldSharedCache(path: String)
    /// Every image of the running system's dyld shared cache, read from its
    /// files rather than from the process.
    case systemDyldSharedCache
}

/// Why a cross-reference request could not run.
public enum CrossReferenceRequestError: Error, LocalizedError, Sendable, Equatable {
    /// A ``CrossReferenceInput/files(paths:architecture:)`` input naming no
    /// file.
    case noFile
    /// No analyzed image has this name or path.
    case imageNotFound(name: String)
    /// No analyzed image defines or imports a symbol of this name.
    case symbolNotFound(name: String)
    /// The symbol names no function's first instruction: a variable, or data.
    case symbolIsNoFunction(name: String)
    /// No analyzed image defines or imports a class of this name.
    case classNotFound(name: String)
    /// No analyzed image — or none of the one named — defines a Swift type
    /// with this mangling.
    case swiftTypeNotFound(mangling: String)
    /// A dyld shared cache's images export no descriptor of a Swift type
    /// with this mangling: the image that defines it must be named, since
    /// working out every image's type keys takes minutes.
    case swiftTypeNeedsImage(mangling: String)
    /// No function of the image the address was looked up in holds it.
    case noFunction(address: UInt64)
    /// Several of the files hold a function at the address; the image must
    /// be named.
    case ambiguousFunction(address: UInt64, imagePaths: [String])
    /// Only a function's callees can be listed.
    case calleesRequireFunction
    /// A file or cache that holds no arm64 code.
    case unsupportedArchitecture(path: String)

    public var errorDescription: String? {
        switch self {
        case .noFile:
            "No Mach-O file to analyze."
        case .imageNotFound(let name):
            "No analyzed image is named '\(name)'."
        case .symbolNotFound(let name):
            "No analyzed image defines or imports a symbol named '\(name)'."
        case .symbolIsNoFunction(let name):
            "The symbol '\(name)' does not name the start of a function."
        case .classNotFound(let name):
            "No analyzed image defines or imports an Objective-C class named '\(name)'."
        case .swiftTypeNotFound(let mangling):
            "No analyzed image defines a Swift type whose mangling is '\(mangling)'."
        case .swiftTypeNeedsImage(let mangling):
            "No image of the dyld shared cache exports a descriptor of '\(mangling)'; name the image that defines it."
        case .noFunction(let address):
            "No function holds the address \(CrossReferenceFormatting.hexadecimal(address))."
        case .ambiguousFunction(let address, let imagePaths):
            "Several images hold a function at \(CrossReferenceFormatting.hexadecimal(address)): \(imagePaths.joined(separator: ", "))."
        case .calleesRequireFunction:
            "Only a function's callees can be listed."
        case .unsupportedArchitecture(let path):
            "\(path) holds no arm64 code; cross references are read from arm64 code only."
        }
    }
}

extension CrossReferenceInput {
    /// The analyzer over the images this input names.
    func makeAnalyzer() throws -> CrossReferenceAnalyzer {
        do {
            switch self {
            case .files(let paths, let architecture):
                guard !paths.isEmpty else { throw CrossReferenceRequestError.noFile }
                // A fat file needs its slice named, as everywhere else on
                // the command line: the one shared loader refuses to pick.
                return try CrossReferenceAnalyzer(machOFiles: paths.map { try MachOSource.file(path: $0, architecture: architecture).load() })
            case .dyldSharedCache(let path):
                return try CrossReferenceAnalyzer(dyldCache: FullDyldCache(url: URL(fileURLWithPath: path)))
            case .systemDyldSharedCache:
                guard let dyldCache = FullDyldCache.cachedHost else { throw MachOSourceError.systemDyldSharedCacheUnavailable }
                return try CrossReferenceAnalyzer(dyldCache: dyldCache)
            }
        } catch let error as CrossReferenceAnalyzer.FileAnalysisError where error.code == .unsupportedArchitecture {
            throw CrossReferenceRequestError.unsupportedArchitecture(path: error.path)
        }
    }

    /// The input, as the JSON document names it.
    var jsonDescription: [String: CrossReferenceJSONValue] {
        switch self {
        case .files(let paths, _):
            ["files": .array(paths.map { .string($0) })]
        case .dyldSharedCache(let path):
            ["dyldSharedCache": .string(path)]
        case .systemDyldSharedCache:
            ["systemDyldSharedCache": .string(FullDyldCache.cachedHost?.url.path ?? "")]
        }
    }
}

extension CrossReferenceAnalyzer {
    /// The positions of the images `names` name — each by its path, or by
    /// its file name (`AppKit`, `libobjc.A.dylib`), which may name more than
    /// one: a cache carries the macOS and the Mac Catalyst variant of some
    /// frameworks. Every image, sorted, when `names` is empty.
    func imageIndices(named names: [String]) throws -> [Int] {
        guard !names.isEmpty else { return Array(0 ..< imageCount) }
        var imageIndices = Set<Int>()
        for name in names {
            let matches = imagePaths.indices.filter { imageIndex in
                let path = imagePaths[imageIndex]
                return path == name || (path as NSString).lastPathComponent == name
            }
            guard !matches.isEmpty else { throw CrossReferenceRequestError.imageNotFound(name: name) }
            imageIndices.formUnion(matches)
        }
        return imageIndices.sorted()
    }
}
