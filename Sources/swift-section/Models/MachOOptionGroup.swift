import ArgumentParser
import Foundation
import MachOFoundation
import SwiftDeclarationRendering

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

    @Option(name: .customLong("dependency-search-path"), help: "Where the images a standalone binary links are looked for — both when a type must be read out of another image's metadata accessor (an availability-conditional opaque type, a noncopyable field type) and when the static field-offset / type-layout comments need a cross-module type's descriptor: a Mach-O file, a dyld shared cache file (dyld_shared_cache_* / dyld_sim_shared_cache_*), or a directory used as a system root under which absolute install names resolve (an iOS 26 or earlier simulator runtime's RuntimeRoot). Repeatable; named paths are consulted before the running system's shared cache. Without it the paths are inferred from where the binary sits on disk, and the running system's shared cache is used.", completion: .file())
    var dependencySearchPaths: [String] = []

    /// A mistyped search path is a usage error, not a silent miss: the
    /// resolver records an unopenable path only as a load failure, which
    /// nothing on the thunk-reading side reports.
    mutating func validate() throws {
        for path in dependencySearchPaths where !FileManager.default.fileExists(atPath: path) {
            throw ValidationError("--dependency-search-path does not exist: \(path)")
        }
    }

    /// The resolver the accessor-thunk rewrites should use when the user
    /// named search paths, else `nil` for the inferring default.
    var accessorThunkResolver: DisassemblingAccessorThunkResolver? {
        guard !dependencySearchPaths.isEmpty else { return nil }
        return DisassemblingAccessorThunkResolver(searchPaths: dependencySearchPaths.map { DependencySearchPath(classifyingPath: $0) })
    }

    /// How the static (offline) layout engine resolves cross-module types:
    /// the user-named search paths first, the running system's shared cache
    /// as the fallback — so a binary can be laid out against the OS version
    /// whose cache was named rather than the host's. Without any path this is
    /// the library default.
    var staticLayoutDependencyResolution: StaticLayoutDependencyResolution {
        guard !dependencySearchPaths.isEmpty else { return .default }
        return .dependencyClosure(searchPaths: dependencySearchPaths.map { DependencySearchPath(classifyingPath: $0) } + [.systemDyldSharedCache])
    }
}

extension AccessorThunkResolution {
    /// Runs `operation` with the user-named search paths in force for every
    /// kind-9 accessor-thunk rewrite it performs, or unchanged when none
    /// were named. The task-local is the one injection point the rendering
    /// layer offers; the CLI is a host like any other.
    static func withResolver<Result>(from options: MachOOptionGroup, _ operation: () async throws -> Result) async rethrows -> Result {
        guard let resolver = options.accessorThunkResolver else { return try await operation() }
        return try await $taskResolver.withValue(resolver, operation: operation)
    }
}
