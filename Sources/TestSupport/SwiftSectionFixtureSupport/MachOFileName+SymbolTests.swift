import Foundation
import MachOFixtureSupport

extension MachOFileName {
    /// The package root, which the SymbolTests fixtures are built under.
    ///
    /// Anchored at this file, `Sources/TestSupport/SwiftSectionFixtureSupport/`,
    /// so a path relative to it climbs three levels to reach the root (see
    /// `AGENTS.md` on `Sources/` grouping and `#filePath`).
    private static let packageRootAnchor = URL(fileURLWithPath: #filePath)

    private static func symbolTestsProduct(_ productName: String) -> MachOFileName {
        MachOFileName(
            path: "../../../Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/\(productName).framework/Versions/A/\(productName)",
            relativeTo: packageRootAnchor
        )
    }

    package static let SymbolTests = symbolTestsProduct("SymbolTests")
    package static let SymbolTestsCore = symbolTestsProduct("SymbolTestsCore")
    /// SymbolTestsCore's resilient-parent dependency. Kept OUT of the shared
    /// suites deliberately: `PerImageCacheEvictionTests` needs an image no
    /// concurrently-running suite touches, so its cache-membership
    /// assertions cannot race another suite's indexer lifecycle.
    package static let SymbolTestsHelper = symbolTestsProduct("SymbolTestsHelper")
}
