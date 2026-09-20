import Foundation
import Testing
import MachOKit
import MachOFoundation
import SwiftDump
import SwiftDeclarationRendering
@testable import MachOTestingSupport

/// The dump path's rendering of an `@objc @implementation` class (evolution
/// proposal `objc-implementation-class-recognition`): everything the binary
/// says, ObjC side first, nothing guessed.
@Suite(.serialized)
struct ObjCImplementationClassDumpTests {
    private func dump(_ variant: ObjCImplementationFixture.Variant, configure: (inout DumperConfiguration) -> Void = { _ in }) async throws -> String {
        let machOFile = try ObjCImplementationFixture.machOFile(variant)
        var configuration = DumperConfiguration.demangleOptions(.test)
        configure(&configuration)
        let classes = ObjCImplementationClass.all(in: machOFile)
        var output = ""
        for objcImplementationClass in classes {
            output += try await objcImplementationClass.dump(using: configuration, in: machOFile).string
            output += "\n"
        }
        return output
    }

    @Test func fullFixtureDumpsBothSides() async throws {
        let output = try await dump(.full)
        #expect(output.contains("@objc @implementation extension Widget {"))
        #expect(output.contains("// ObjC class Widget: NSObject, class_ro_t flags 0x184, instanceStart 8, instanceSize 40"))
        #expect(output.contains("// Evidence: metadata accessor _$sSo6WidgetCMa, 3 field-offset globals, Swift symbols at 9 method implementations"))
        #expect(output.contains("// Implemented in Swift module \(ObjCImplementationFixture.moduleName)"))
        #expect(output.contains("/* Stored properties (ObjC ivars) */"))
        #expect(output.contains("var title: Swift.String // offset 0x8, size 16, alignment 8, encoding \"?\", "))
        // `.test` demangle options print sugared types.
        #expect(output.contains("var swiftOnlyCache: [Swift.Int] // offset 0x20, size 8, alignment 8, encoding \"\", "))
        #expect(output.contains("not exposed to ObjC"))
        #expect(output.contains("/* ObjC instance methods */"))
        #expect(output.contains("-[Widget initWithTitle:] // types \"@24@0:8@16\", imp 0x"))
        #expect(output.contains("-[Widget .cxx_destruct] // types \"v16@0:8\", imp 0x"))
        #expect(output.contains("/* ObjC properties */"))
        #expect(output.contains("title // T@\"NSString\",N,C"))
        #expect(output.contains("/* Swift Function (In Extension) */"))
        #expect(output.contains("Widget.refresh() -> ()"))
        // One class only: the clang class and the Swift class are not candidates.
        #expect(!output.contains("extension ClangWidget"))
        #expect(!output.contains("PlainSwiftSibling"))
    }

    @Test func fieldOffsetAndAddressCommentsFollowTheDumpFlags() async throws {
        let output = try await dump(.full) { configuration in
            configuration.printFieldOffset = true
            configuration.printMemberAddress = true
        }
        #expect(output.contains("    // Field offset: 0x18\n    var count: Swift.Int // offset 0x18"))
        #expect(output.contains("    // Address: 0x"))
    }

    @Test func fullyStrippedDumpIsHonestAboutWhatIsMissing() async throws {
        let output = try await dump(.strippedEverything)
        #expect(output.hasPrefix("@objc @implementation /* inferred from ObjC class data: 2 ivars carry Swift-style type encodings */ extension Widget {"))
        #expect(output.contains("// Evidence: inferred from ObjC class data: 2 ivars carry Swift-style type encodings"))
        #expect(output.contains("title // offset 0x8, size 16, alignment 8, encoding \"?\", Swift type not recoverable"))
        // IMPs with no symbol print as addresses only.
        #expect(output.contains("-[Widget refresh] // types \"v16@0:8\", imp 0x"))
        #expect(!output.contains("To\n"))
        #expect(!output.contains("/* Swift "))
    }
}
