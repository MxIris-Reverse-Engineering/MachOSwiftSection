import Foundation
import MachOKit
import MachOExtensions
import UniformTypeIdentifiers

package func loadFromFile(named: MachOFileName) throws -> File {
    let url = URL(fileURLWithPath: named.rawValue)
    return try File.loadFromFile(url: url)
}

extension MachOImage {
    package init?(named: MachOImageName) {
        self.init(name: named.rawValue)
    }
}

extension DyldCache {
    package convenience init(path: DyldSharedCachePath) throws {
        try self.init(url: URL(fileURLWithPath: path.rawValue))
    }

    package func machOFile(named: MachOImageName) -> MachOFile? {
        machOFile(by: .name(named.rawValue))
    }
}

extension String {
    package func print() {
        Swift.print(self)
    }
}
