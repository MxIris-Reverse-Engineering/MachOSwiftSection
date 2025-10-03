import Foundation
import Dependencies

extension URL {
    package func createDirectoryIfNeeded(withIntermediateDirectories createIntermediates: Bool = true) throws {
        @Dependency(\.fileManager)
        var fileManager
        if fileManager.fileExists(atPath: path(percentEncoded: false)) { return }
        try fileManager.createDirectory(at: self, withIntermediateDirectories: createIntermediates)
    }
}

extension DependencyValues {
    package var fileManager: FileManager {
        set { self[FileManagerKey.self] = newValue }
        get { self[FileManagerKey.self] }
    }
}

private enum FileManagerKey: DependencyKey, @unchecked Sendable {
    package static let liveValue: FileManager = .default
    package static let testValue: FileManager = .default
}

extension FileManager: @retroactive @unchecked Sendable {}
