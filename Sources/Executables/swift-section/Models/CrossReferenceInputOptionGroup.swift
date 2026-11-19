import ArgumentParser
import Foundation
import SwiftSectionKit

/// The input of `refs` and `symbolicate`: a whole dyld shared cache, or a set
/// of files read together. Unlike the other subcommands' option groups it
/// names no single image — the cache is read whole — so the cache path is the
/// option's own value.
struct CrossReferenceInputOptionGroup: ParsableArguments, Sendable {
    @Option(name: .customLong("dyld-shared-cache"), help: "Analyze every image of the dyld shared cache at this path (dyld_shared_cache_arm64e, its subcaches found beside it).", completion: .file())
    var dyldSharedCachePath: String?

    @Flag(help: "Analyze every image of the running system's dyld shared cache, read from its files.")
    var usesSystemDyldSharedCache: Bool = false

    @Option(name: .shortAndLong, help: "The slice of a fat file to read (required for fat binaries): arm64 or arm64e, cross references being read from arm64 code only.")
    var architecture: Architecture?

    @Option(name: .customLong("in-image"), help: "An image to look in, by its path or its file name (AppKit, libobjc.A.dylib). Repeatable; without it every image is.")
    var imageNames: [String] = []

    /// The input these options and `filePaths` name: exactly one of a cache,
    /// the running system's cache, or files.
    func input(filePaths: [String]) throws -> CrossReferenceInput {
        switch (dyldSharedCachePath, usesSystemDyldSharedCache, filePaths.isEmpty) {
        case (let cachePath?, false, true):
            return .dyldSharedCache(path: cachePath)
        case (nil, true, true):
            return .systemDyldSharedCache
        case (nil, false, false):
            return .files(paths: filePaths, architecture: architecture)
        case (nil, false, true):
            throw ValidationError("Name what to analyze: Mach-O files, --dyld-shared-cache <path>, or --uses-system-dyld-shared-cache.")
        default:
            throw ValidationError("Name one input: Mach-O files, --dyld-shared-cache <path>, or --uses-system-dyld-shared-cache.")
        }
    }
}

/// An address on the command line: hexadecimal with `0x`, or decimal.
func parseAddress(_ text: String) throws -> UInt64 {
    let value: UInt64?
    if text.lowercased().hasPrefix("0x") {
        value = UInt64(text.dropFirst(2), radix: 16)
    } else {
        value = UInt64(text)
    }
    guard let value else { throw ValidationError("'\(text)' is no address: write it in hexadecimal with 0x, or in decimal.") }
    return value
}
