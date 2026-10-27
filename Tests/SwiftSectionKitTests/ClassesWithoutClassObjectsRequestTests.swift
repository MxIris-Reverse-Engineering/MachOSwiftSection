import Foundation
import Testing
import SwiftSectionKit
@testable import MachOTestingSupport

/// The `objc` requests list the Swift classes an image keeps no class object
/// for (evolution proposal `objc-classes-without-class-objects`), their
/// `class_ro_t` read from Swift metadata and handed to the ObjC indexer:
/// generic classes, and the classes `__objc_stublist` registers.
@Suite(.serialized, ExclusiveImageAccess(ClassesWithoutClassObjectsFixture.moduleName))
struct ClassesWithoutClassObjectsRequestTests {
    private static let moduleName = ClassesWithoutClassObjectsFixture.moduleName

    private static let kitModuleName = ClassesWithoutClassObjectsFixture.kitModuleName

    private static func source() throws -> MachOSource {
        .file(path: try ClassesWithoutClassObjectsFixture.libraryURL(.full).path, architecture: nil)
    }

    @Test("An ObjC dump lists the classes without a class object, under the comment naming why")
    func dumpListsClassesWithoutClassObjects() async throws {
        let output = RecordingOutput()
        try await ObjCDumpRequest(source: try Self.source(), kinds: [.classes]).run(output: output)
        let product = output.printedProduct

        #expect(product.contains("// Generic Swift class, instantiated at runtime\n@interface \(Self.moduleName).GenericWidget<A> : NSObject"), "\(product)")
        #expect(product.contains("// Generic Swift class, instantiated at runtime\n@interface \(Self.moduleName).Namespace.NestedGenericWidget<A, B> : NSObject"), "\(product)")
        #expect(product.contains("// Generic Swift class, instantiated at runtime\n@interface \(Self.moduleName).GenericNativeRoot<A> : _TtCs12_SwiftObject"), "\(product)")
        #expect(product.contains("// Swift class with resilient ancestry, registered through __objc_stublist\n@interface _TtC\(Self.moduleName.count)\(Self.moduleName)14ResilientChild : \(Self.kitModuleName).ResilientBase"), "\(product)")
        #expect(product.contains("// Swift class with generic ancestry, registered through __objc_stublist\n@interface _TtC\(Self.moduleName.count)\(Self.moduleName)16ConcreteSubclass : \(Self.moduleName).GenericWidget<A>"), "\(product)")
        // Generic ancestry on the native object model: nothing registers it.
        #expect(!product.contains("NativeConcreteSubclass"), "\(product)")
        // The methods come from the templates.
        #expect(product.contains("- (void)poke;"), "\(product)")
        #expect(product.contains("+ (void)classPoke;"), "\(product)")
        #expect(product.contains("- (void)resilientPoke;"), "\(product)")
        #expect(product.contains("- (void)concretePoke;"), "\(product)")
        // The negative control is listed as before.
        #expect(product.contains("@interface _TtC\(Self.moduleName.count)\(Self.moduleName)11PlainWidget : NSObject"), "\(product)")
    }
}
