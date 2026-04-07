import ArgumentParser

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
}
