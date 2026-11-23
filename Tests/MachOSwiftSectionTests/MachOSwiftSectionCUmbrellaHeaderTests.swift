import Foundation
import Testing

/// `MachOSwiftSectionC`'s umbrella header has to include every header of the
/// module. One it leaves out stays out of the module, and no build says so:
/// Xcode reuses the module it built before the header existed, without the
/// warning a fresh build of the module would give.
@Suite
struct MachOSwiftSectionCUmbrellaHeaderTests {
    @Test func umbrellaHeaderIncludesEveryHeader() throws {
        let includeDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ABI/MachOSwiftSectionC/include")
        let umbrellaHeaderName = "MachOSwiftSectionC.h"
        let umbrellaHeader = try String(
            contentsOf: includeDirectory.appendingPathComponent(umbrellaHeaderName),
            encoding: .utf8
        )
        let headerNames = try FileManager.default.contentsOfDirectory(atPath: includeDirectory.path)
            .filter { $0.hasSuffix(".h") && $0 != umbrellaHeaderName }
            .sorted()
        #expect(!headerNames.isEmpty)
        for headerName in headerNames {
            #expect(umbrellaHeader.contains("\n#include \"\(headerName)\"\n"), "\(umbrellaHeaderName) does not include \(headerName)")
        }
    }
}
