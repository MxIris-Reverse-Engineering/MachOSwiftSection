import Foundation
import MachOKit
import MachOFoundation
import Rainbow
import Semantic

extension MachOFile {
    static func load(options: MachOOptionGroup) throws -> MachOFile {
        if options.isDyldSharedCache || options.usesSystemDyldSharedCache {
            let dyldCache: DyldCache
            if options.usesSystemDyldSharedCache {
                if let host = DyldCache.host {
                    dyldCache = host
                } else {
                    throw SwiftSectionCommandError.unsupportedSystemVersionForDyldSharedCache
                }
            } else {
                let url = try URL(fileURLWithPath: required(options.filePath, error: SwiftSectionCommandError.missingFilePath))
                dyldCache = try DyldCache(url: url)
            }

            if let _ = options.cacheImagePath, let _ = options.cacheImageName {
                throw SwiftSectionCommandError.ambiguousCacheImageNameAndCacheImagePath
            } else if let cacheImageName = options.cacheImageName {
                return try required(dyldCache.machOFile(by: .name(cacheImageName)), error: SwiftSectionCommandError.imageNotFound)
            } else if let cacheImagePath = options.cacheImagePath {
                return try required(dyldCache.machOFile(by: .path(cacheImagePath)), error: SwiftSectionCommandError.imageNotFound)
            } else {
                throw SwiftSectionCommandError.missingCacheImageNameOrCacheImagePath
            }
        } else {
            let url = try URL(fileURLWithPath: required(options.filePath, error: SwiftSectionCommandError.missingFilePath))
            let file = try File.loadFromFile(url: url)
            switch file {
            case .machO(let machOFile):
                return machOFile
            case .fat(let fatFile):
                return try required(fatFile.machOFiles().first { $0.header.cpu.subtype == options.architecture?.cpu ?? CPU.current?.subtype } ?? fatFile.machOFiles().first, error: SwiftSectionCommandError.invalidArchitecture)
            }
        }
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
            case .typeName:
                return "#2E0D6E"
            case .typeDeclaration:
                return "#004975"
            case .functionName,
                 .memberName:
                return "#5C2699"
            case .functionDeclaration,
                 .memberDeclaration:
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
            case .typeName:
                return "#D0A8FF"
            case .typeDeclaration:
                return "#5DD8FF"
            case .functionName,
                 .memberName:
                return "#A167E6"
            case .functionDeclaration,
                 .memberDeclaration:
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
