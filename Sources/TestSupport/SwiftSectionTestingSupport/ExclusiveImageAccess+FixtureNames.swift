import Foundation
import MachOTestingSupport
import SwiftSectionFixtureSupport

extension ExclusiveImageAccess {
    /// Spelled from the fixture's name so a typo is a compile error rather
    /// than a silently ineffective exclusion. `package`, matching the fixture
    /// names this package adds — a suite reaching the image by a hand-built
    /// path (which is how the sharing went unnoticed) uses the `String`
    /// initializer with the same key, the image's name.
    package init(_ fileName: MachOFileName) {
        self.init(fileName.exclusiveAccessKey)
    }

    package init(_ imageName: MachOImageName) {
        self.init(imageName.exclusiveAccessKey)
    }
}

extension MachOFileName {
    /// What ``ExclusiveImageAccess`` keys this file by: the name of the image
    /// it holds, the last path component without its extension, so that a
    /// suite naming a fixture by its file and one naming it by its image
    /// (`MachOImageName`) exclude each other.
    package var exclusiveAccessKey: String {
        url.deletingPathExtension().lastPathComponent
    }
}

extension MachOImageName {
    /// What ``ExclusiveImageAccess`` keys this image by: its name, the same
    /// key as the file it was loaded from (``MachOFileName/exclusiveAccessKey``).
    package var exclusiveAccessKey: String {
        name
    }
}
