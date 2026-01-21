import Foundation
import MachOKit

extension File {
    package static func loadFromFile(url: URL) throws -> File {
        var url = url
        if let executableURL = Bundle(url: url)?.executableURL {
            url = executableURL
        }
        return try MachOKit.loadFromFile(url: url)
    }

    package var machOFiles: [MachOFile] {
        switch self {
        case .machO(let machOFile):
            return [machOFile]
        case .fat(let fatFile):
            return (try? fatFile.machOFiles()) ?? []
        }
    }
}
