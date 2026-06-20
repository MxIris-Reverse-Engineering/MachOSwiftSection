import Foundation
import MachOKit
import MachOFoundation
import Rainbow
import Semantic

extension MachOFile {
    /// The core loader shared by every command: either a thin/fat Mach-O file at
    /// `filePath` (selecting `architecture` for a fat binary), or an image
    /// extracted from a dyld shared cache (the running system's, or the cache at
    /// `filePath`). Centralizing it keeps every command's fat-binary affordance
    /// (the `availableArchitectures` hint) and cache-image disambiguation
    /// identical instead of each command re-deriving them and drifting.
    static func load(
        filePath: String?,
        isDyldSharedCache: Bool,
        usesSystemDyldSharedCache: Bool,
        cacheImageName: String?,
        cacheImagePath: String?,
        architecture: Architecture?
    ) throws -> MachOFile {
        if isDyldSharedCache || usesSystemDyldSharedCache {
            let dyldCache: DyldCache
            if usesSystemDyldSharedCache {
                if let host = DyldCache.host {
                    dyldCache = host
                } else {
                    throw SwiftSectionCommandError.unsupportedSystemVersionForDyldSharedCache
                }
            } else {
                let url = try URL(fileURLWithPath: required(filePath, error: SwiftSectionCommandError.missingFilePath))
                dyldCache = try DyldCache(url: url)
            }

            if cacheImagePath != nil, cacheImageName != nil {
                throw SwiftSectionCommandError.ambiguousCacheImageNameAndCacheImagePath
            } else if let cacheImageName {
                return try required(dyldCache.machOFile(by: .name(cacheImageName)), error: SwiftSectionCommandError.imageNotFound)
            } else if let cacheImagePath {
                return try required(dyldCache.machOFile(by: .path(cacheImagePath)), error: SwiftSectionCommandError.imageNotFound)
            } else {
                throw SwiftSectionCommandError.missingCacheImageNameOrCacheImagePath
            }
        } else {
            let url = try URL(fileURLWithPath: required(filePath, error: SwiftSectionCommandError.missingFilePath))
            let file = try File.loadFromFile(url: url)
            switch file {
            case .machO(let machOFile):
                return machOFile
            case .fat(let fatFile):
                let machOFiles = try fatFile.machOFiles()
                guard let architecture else {
                    let availableArchitectures = machOFiles.map { machOFile -> String in
                        Architecture(cpu: machOFile.header.cpu)?.rawValue ?? machOFile.header.cpu.description
                    }
                    throw SwiftSectionCommandError.fatBinaryRequiresArchitecture(availableArchitectures: availableArchitectures)
                }
                return try required(machOFiles.first { $0.header.cpu.subtype == architecture.cpu }, error: SwiftSectionCommandError.invalidArchitecture)
            }
        }
    }

    static func load(options: MachOOptionGroup) throws -> MachOFile {
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

extension String {
    func withColorHex(for type: SemanticType, colorScheme: SemanticColorScheme) -> String? {
        switch colorScheme {
        case .none:
            return nil
        case .light:
            switch type {
            case .comment:
                return "#56606B"
            case .keyword:
                return "#C33381"
            case .type(_, .name):
                return "#2E0D6E"
            case .type(_, .declaration):
                return "#004975"
            case .function(.name),
                 .member(.name):
                return "#5C2699"
            case .function(.declaration),
                 .member(.declaration),
                 .variable:
                return "#0F68A0"
            case .numeric:
                return "#000BFF"
            default:
                return nil
            }
        case .dark:
            switch type {
            case .comment:
                return "#6C7987"
            case .keyword:
                return "#F2248C"
            case .type(_, .name):
                return "#D0A8FF"
            case .type(_, .declaration):
                return "#5DD8FF"
            case .function(.name),
                 .member(.name):
                return "#A167E6"
            case .function(.declaration),
                 .member(.declaration):
                return "#41A1C0"
            case .numeric:
                return "#D0BF69"
            default:
                return nil
            }
        }
    }

    func withColor(for type: SemanticType, colorScheme: SemanticColorScheme) -> String {
        if let colorHex = withColorHex(for: type, colorScheme: colorScheme) {
            let resolved = hex(colorHex, to: .bit24)
            return resolved
        } else if type == .error {
            return red
        } else {
            return self
        }
    }
}
