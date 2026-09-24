import Foundation
import MachOKit
import MachOSwiftSection
import SwiftLayout
import Testing

/// Real compiler-emitted records, independent of the shared SymbolTestsCore
/// binary. The source layouts below are the expected values, not a snapshot of
/// the layout calculator's own output.
@Suite(.serialized)
struct NestedFieldExtentTests {
    private static let fixtureSource = """
    import ExtentFields
    public struct PaddedCoordinates {
        public var horizontal: Int32
        public var vertical: Int64
        public var flag: Bool
    }
    public struct Wrapper<Value> { public var value: Value }
    public struct UnresolvedEnvelope<Element> { public var coordinates: Wrapper<Element> }
    public enum CoordinateChoice {
        case first(PaddedCoordinates)
        case second(PaddedCoordinates)
        indirect case boxed(PaddedCoordinates)
    }
    public struct Envelope {
        public var coordinates: PaddedCoordinates
        public var wrapped: Wrapper<Wrapper<Int64>>
        public var choice: CoordinateChoice
        public var hidden: HiddenFields
        public var packed: PackedFields
    }
    public final class FixtureAnchor {}
    """

    private static let importedFields = """
    typedef struct HiddenFields {
        unsigned int hidden : 1;
        short visible;
    } HiddenFields;
    #pragma pack(push, 4)
    typedef struct PackedFields {
        long long value;
        int flags;
        int scale;
        long long epoch;
    } PackedFields;
    #pragma pack(pop)
    """

    private func tree(forFieldNamed fieldName: String, inStructNamed structName: String = "Envelope") throws -> [NestedFieldOffset] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NestedFieldExtents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourcePath = directory.appendingPathComponent("Fixture.swift")
        let binaryPath = directory.appendingPathComponent("libNestedExtentFixture.dylib")
        try Self.fixtureSource.write(to: sourcePath, atomically: true, encoding: .utf8)
        try Self.importedFields.write(to: directory.appendingPathComponent("Fields.h"), atomically: true, encoding: .utf8)
        try "module ExtentFields { header \"Fields.h\" export * }".write(
            to: directory.appendingPathComponent("module.modulemap"), atomically: true, encoding: .utf8
        )
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = [
            "swiftc", "-emit-library", "-module-name", "NestedExtentFixture",
            "-module-cache-path", directory.appendingPathComponent("ModuleCache").path,
            "-I", directory.path, sourcePath.path, "-o", binaryPath.path,
        ]
        try compiler.run()
        compiler.waitUntilExit()
        try #require(compiler.terminationStatus == 0, "The fixture must compile before testing layout")
        let machOFile = try MachOFile(url: binaryPath)
        let calculator = try StaticLayoutCalculator(machO: machOFile)
        for typeContext in try machOFile.swift.types {
            guard case .struct(let structType) = typeContext,
                  try structType.descriptor.name(in: machOFile) == structName else { continue }
            let records = try structType.descriptor.fieldDescriptor(in: machOFile).records(in: machOFile)
            let record = try #require(records.first { (try? $0.fieldName(in: machOFile)) == fieldName })
            return calculator.nestedFieldOffsetTree(
                forMangledTypeName: try record.mangledTypeName(in: machOFile),
                baseOffset: 32, depthLimit: 8
            )
        }
        Issue.record("The compiler fixture did not emit \(structName) metadata")
        return []
    }

    @Test func nestedSizesExcludeAlignmentPadding() throws {
        let fields = try tree(forFieldNamed: "coordinates")
        #expect(fields.map(\.fieldName) == ["horizontal", "vertical", "flag"])
        #expect(fields.map(\.offset) == [32, 40, 48])
        #expect(fields.map(\.byteWidth) == [4, 8, 1])
    }

    @Test func substitutedWrapperFieldsRetainTheirOwnExtents() throws {
        let fields = try tree(forFieldNamed: "wrapped")
        let outerField = try #require(fields.first)
        let innerField = try #require(outerField.children.first)
        #expect(outerField.fieldName == "value")
        #expect(innerField.fieldName == "value")
        #expect(outerField.offset == 32 && innerField.offset == 32)
        #expect(outerField.byteWidth == 8 && innerField.byteWidth == 8)
    }

    @Test func enumAlternativesNeverClaimUnconditionalExtents() throws {
        let fields = try tree(forFieldNamed: "choice")
        #expect(fields.map(\.fieldName) == ["first", "second", "boxed"])
        for field in fields {
            #expect(field.byteWidth == nil)
            if field.fieldName == "boxed" {
                #expect(field.children.isEmpty)
            } else {
                #expect(field.children.map(\.fieldName) == ["horizontal", "vertical", "flag"])
                #expect(field.children.allSatisfy { $0.byteWidth == nil })
            }
        }
    }

    @Test func hiddenForeignStorageCannotProduceNestedOffsets() throws {
        #expect(try tree(forFieldNamed: "hidden").isEmpty)
    }

    @Test func unresolvedGenericStorageCannotProduceNestedExtents() throws {
        #expect(try tree(forFieldNamed: "coordinates", inStructNamed: "UnresolvedEnvelope").isEmpty)
    }

    @Test func provenPackedForeignFieldsKeepTheirSizes() throws {
        let fields = try tree(forFieldNamed: "packed")
        #expect(fields.map(\.fieldName) == ["value", "flags", "scale", "epoch"])
        #expect(fields.map(\.offset) == [32, 40, 44, 48])
        #expect(fields.map(\.byteWidth) == [8, 4, 4, 8])
    }

    @Test func manuallyCreatedNodesDefaultToUnknownExtent() {
        let field = NestedFieldOffset(fieldName: "value", typeName: "Int", offset: 0, children: [])
        #expect(field.byteWidth == nil)
    }

    @Test func crossImageGenericFieldsUseTheSuppliedDependency() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NestedExtentDependency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sources = [
            ("ExtentDependency", """
            public struct CoordinatePair<Element> {
                public var horizontal: Element
                public var vertical: Element
            }
            public final class DependencyAnchor {}
            """),
            ("ExtentRoot", """
            import ExtentDependency
            public struct Envelope { public var coordinates: CoordinatePair<Int16> }
            public final class RootAnchor {}
            """),
        ]
        for (moduleName, source) in sources {
            let sourcePath = directory.appendingPathComponent("\(moduleName).swift")
            try source.write(to: sourcePath, atomically: true, encoding: .utf8)
            let compiler = Process()
            compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            compiler.arguments = [
                "swiftc", "-emit-library", "-emit-module", "-module-name", moduleName,
                "-emit-module-path", directory.appendingPathComponent("\(moduleName).swiftmodule").path,
                "-module-cache-path", directory.appendingPathComponent("ModuleCache").path,
                "-I", directory.path, "-L", directory.path,
                "-Xlinker", "-install_name", "-Xlinker", "@rpath/lib\(moduleName).dylib",
                sourcePath.path, "-o", directory.appendingPathComponent("lib\(moduleName).dylib").path,
            ] + (moduleName == "ExtentRoot" ? ["-lExtentDependency"] : [])
            try compiler.run()
            compiler.waitUntilExit()
            try #require(compiler.terminationStatus == 0)
        }
        let rootFile = try MachOFile(url: directory.appendingPathComponent("libExtentRoot.dylib"))
        let rootType = try #require(try rootFile.swift.types.first { typeContext in
            guard case .struct(let structType) = typeContext else { return false }
            return (try? structType.descriptor.name(in: rootFile)) == "Envelope"
        })
        guard case .struct(let envelope) = rootType else { return }
        let record = try #require(try envelope.descriptor.fieldDescriptor(in: rootFile).records(in: rootFile).first)
        let typeName = try record.mangledTypeName(in: rootFile)
        let unavailableUniverse = try ImageUniverse.dependencyClosure(root: rootFile, searchPaths: [])
        #expect(StaticLayoutCalculator(imageUniverse: unavailableUniverse).nestedFieldOffsetTree(
            forMangledTypeName: typeName, baseOffset: 32, depthLimit: 4
        ).isEmpty)
        let suppliedUniverse = try ImageUniverse.dependencyClosure(root: rootFile, searchPaths: [
            .machOFile(path: directory.appendingPathComponent("libExtentDependency.dylib").path),
        ])
        let fields = StaticLayoutCalculator(imageUniverse: suppliedUniverse).nestedFieldOffsetTree(
            forMangledTypeName: typeName, baseOffset: 32, depthLimit: 4
        )
        #expect(fields.map(\.fieldName) == ["horizontal", "vertical"])
        #expect(fields.map(\.offset) == [32, 34])
        #expect(fields.map(\.byteWidth) == [2, 2])
    }
}
