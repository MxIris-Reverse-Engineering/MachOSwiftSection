import Foundation
import MachOKit

/// Manages the loaded Mach-O file state across tool calls.
///
/// Loading a Mach-O file (especially from dyld shared cache) is expensive,
/// so this actor maintains the loaded state for reuse.
actor BinarySession {
    private(set) var machOFile: MachOFile?
    private(set) var filePath: String?

    func load(path: String, architecture: String? = nil) throws -> String {
        var url = URL(fileURLWithPath: path)
        if let executableURL = Bundle(url: url)?.executableURL {
            url = executableURL
        }
        let file = try MachOKit.loadFromFile(url: url)
        switch file {
        case .machO(let machO):
            self.machOFile = machO
            self.filePath = path
            return describeBinary(machO, path: path)
        case .fat(let fatFile):
            let targetCPU: CPUSubType? = architecture.flatMap { archString in
                switch archString.lowercased() {
                case "arm64": return .arm64(.arm64_all)
                case "arm64e": return .arm64(.arm64e)
                case "x86_64": return .x86(.x86_64_all)
                default: return nil
                }
            }
            guard let machO = try fatFile.machOFiles().first(where: {
                $0.header.cpu.subtype == targetCPU ?? CPU.current?.subtype
            }) ?? fatFile.machOFiles().first else {
                throw SessionError.invalidArchitecture
            }
            self.machOFile = machO
            self.filePath = path
            return describeBinary(machO, path: path)
        }
    }

    func loadFromDyldCache(
        imageName: String? = nil,
        imagePath: String? = nil,
        cachePath: String? = nil
    ) throws -> String {
        let dyldCache: DyldCache
        if let cachePath {
            let url = URL(fileURLWithPath: cachePath)
            dyldCache = try DyldCache(url: url)
        } else if let host = DyldCache.host {
            dyldCache = host
        } else {
            throw SessionError.dyldCacheNotAvailable
        }

        let machO: MachOFile?
        if let imageName {
            machO = dyldCache.machOFiles().first {
                let path = $0.imagePath
                let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                return fileName == imageName
            }
        } else if let imagePath {
            machO = dyldCache.machOFiles().first {
                $0.imagePath == imagePath
            }
        } else {
            throw SessionError.missingImageIdentifier
        }

        guard let machO else {
            throw SessionError.imageNotFound
        }

        self.machOFile = machO
        self.filePath = imageName ?? imagePath
        return describeBinary(machO, path: self.filePath ?? "<dyld cache>")
    }

    func requireMachO() throws -> MachOFile {
        guard let machOFile else {
            throw SessionError.noBinaryLoaded
        }
        return machOFile
    }

    private func describeBinary(_ machO: MachOFile, path: String) -> String {
        var lines: [String] = []
        lines.append("Binary loaded: \(path)")
        lines.append("CPU: \(machO.header.cpu)")
        lines.append("File type: \(machO.header.fileType)")
        return lines.joined(separator: "\n")
    }
}

enum SessionError: LocalizedError {
    case noBinaryLoaded
    case invalidArchitecture
    case dyldCacheNotAvailable
    case missingImageIdentifier
    case imageNotFound

    var errorDescription: String? {
        switch self {
        case .noBinaryLoaded:
            "No binary is currently loaded. Use the 'open_binary' or 'open_dyld_cache_image' tool first."
        case .invalidArchitecture:
            "The specified architecture is not found in the binary."
        case .dyldCacheNotAvailable:
            "The system dyld shared cache is not available."
        case .missingImageIdentifier:
            "Either imageName or imagePath must be provided."
        case .imageNotFound:
            "The specified image was not found in the dyld shared cache."
        }
    }
}
