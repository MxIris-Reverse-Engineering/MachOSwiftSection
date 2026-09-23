import ArgumentParser
import MachOKit

/// How the `objc` subcommands get at the binary: a path on disk, or an image
/// inside a dyld shared cache (the running system's, or a cache file given by
/// path).
///
/// Spelled exactly like the Swift commands' ``MachOOptionGroup``, so `-p` /
/// `-n` / `--architecture` mean the same thing on both sides of the tool. It is
/// a separate type because that one also carries `--dependency-search-path`,
/// which only the Swift reading paths honor; sharing it would give every
/// `objc` subcommand an option that does nothing.
struct ObjCMachOOptionGroup: ParsableArguments, Sendable {
    @Argument(help: "The path to the Mach-O file or dyld shared cache to dump.", completion: .file())
    var filePath: String?

    @Option(name: [.long, .customShort("p")], help: "The path to the dyld shared cache image. If filePath is a Mach-O file, this option is ignored.")
    var cacheImagePath: String?

    @Option(name: [.long, .customShort("n")], help: "The name of the dyld shared cache image. If filePath is a Mach-O file, this option is ignored.")
    var cacheImageName: String?

    @Flag(name: [.customLong("dyld-shared-cache")], help: "The flag to indicate if the Mach-O file is a dyld shared cache.")
    var isDyldSharedCache: Bool = false

    @Flag(help: "Use the current dyld shared cache instead of the specified one. This option is ignored if filePath is a Mach-O file.")
    var usesSystemDyldSharedCache: Bool = false

    @Option(name: .shortAndLong, help: "The architecture of the Mach-O file. If not specified, the current architecture will be used.")
    var architecture: Architecture?

    /// How to name the analyzed image in a diagnostic: the spelling the caller
    /// actually typed, so the note points back at their own command line rather
    /// than at an install name they never mentioned. (For a plain executable
    /// the Mach-O's own `imagePath` is often the empty string anyway.)
    var imageDescription: String {
        cacheImageName ?? cacheImagePath ?? filePath ?? "the system dyld shared cache"
    }
}

extension MachOFile {
    static func load(options: ObjCMachOOptionGroup) throws -> MachOFile {
        try load(
            filePath: options.filePath,
            isDyldSharedCache: options.isDyldSharedCache,
            usesSystemDyldSharedCache: options.usesSystemDyldSharedCache,
            cacheImageName: options.cacheImageName,
            cacheImagePath: options.cacheImagePath,
            architecture: options.architecture
        )
    }
}
