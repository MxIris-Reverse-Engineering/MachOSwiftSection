import Foundation
import MachOKit
import MachOExtensions
import UniformTypeIdentifiers

package func loadFromFile(named: MachOFileName) throws -> File {
    let url: URL
    let filePath = named.rawValue
    if filePath.starts(with: "../") || filePath.starts(with: "./") {
        url = URL(fileURLWithPath: filePath, relativeTo: URL(fileURLWithPath: #filePath))
    } else {
        url = URL(fileURLWithPath: filePath)
    }
    return try File.loadFromFile(url: url)
}

extension MachOImage {
    package init?(named: MachOImageName) {
        self.init(name: named.rawValue)
    }
}

extension FullDyldCache {
    package convenience init(path: DyldSharedCachePath) throws {
        try self.init(url: URL(fileURLWithPath: path.rawValue))
    }

    package func machOFile(named: MachOImageName) -> MachOFile? {
        machOFile(by: .name(named.rawValue))
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

extension CustomStringConvertible {
    package func print() {
        #if !SILENT_TEST
        Swift.print(self)
        #endif
    }
}

extension Error {
    package func print() {
        #if !SILENT_TEST
        Swift.print(self)
        #endif
    }
}
