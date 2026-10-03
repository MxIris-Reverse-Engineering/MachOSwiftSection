import ArgumentParser
import Foundation
import MachOFoundation
import SwiftSectionKit

struct MachOOptionGroup: ParsableArguments, Sendable {
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

    @Option(name: .customLong("dependency-search-path"), help: "Where the images a standalone binary links are looked for — when a type must be read out of another image's metadata accessor (an availability-conditional opaque type, a noncopyable field type), when the static field-offset / type-layout comments need a cross-module type's descriptor, and when a class's ObjC ancestor chain (the `override` keyword, the explicit-selector verdict) crosses into another image: a Mach-O file, a dyld shared cache file (dyld_shared_cache_* / dyld_sim_shared_cache_*), or a directory used as a system root under which absolute install names resolve (an iOS 26 or earlier simulator runtime's RuntimeRoot). Repeatable; named paths are consulted before the running system's shared cache. Without it the paths are inferred from where the binary sits on disk, and the running system's shared cache is used.", completion: .file())
    var dependencySearchPaths: [String] = []

    /// A mistyped search path is a usage error, not a silent miss: the
    /// resolver records an unopenable path only as a load failure, which
    /// nothing on the thunk-reading side reports.
    mutating func validate() throws {
        for path in dependencySearchPaths where !FileManager.default.fileExists(atPath: path) {
            throw ValidationError("--dependency-search-path does not exist: \(path)")
        }
    }

    /// The image these options name.
    func machOSource() throws -> MachOSource {
        try makeMachOSource(
            filePath: filePath,
            isDyldSharedCache: isDyldSharedCache,
            usesSystemDyldSharedCache: usesSystemDyldSharedCache,
            cacheImageName: cacheImageName,
            cacheImagePath: cacheImagePath,
            architecture: architecture
        )
    }

    /// `--dependency-search-path`, each path classified as a Mach-O file, a
    /// dyld shared cache or a system root.
    var dependencySearchPathValues: [DependencySearchPath] {
        dependencySearchPaths.map { DependencySearchPath(classifyingPath: $0) }
    }
}
