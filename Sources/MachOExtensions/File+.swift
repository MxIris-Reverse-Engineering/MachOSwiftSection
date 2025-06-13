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
}
