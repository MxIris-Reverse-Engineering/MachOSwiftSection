import Foundation

package enum FixtureLoadError: Error, CustomStringConvertible {
    case fixtureFileMissing(path: String)
    case imageNotFoundAfterDlopen(path: String, dlerror: String?)

    package var description: String {
        switch self {
        case .fixtureFileMissing(let path):
            return """
            Fixture binary not found at \(path).
            Build it with:
              xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \\
                         -scheme SymbolTestsCore -configuration Release build
            """
        case .imageNotFoundAfterDlopen(let path, let dlerror):
            return """
            dlopen succeeded but MachOImage(name:) returned nil for \(path).
            dlerror: \(dlerror ?? "<none>")
            """
        }
    }
}
