import Foundation
import Testing
import MachOKit
import MachOFoundation
@_spi(Internals) import Demangling
@testable import MachOSwiftSection
@_spi(Internals) @testable import SwiftInspection

// Evolution proposal `type-import-info-identity`: a descriptor-derived
// demangling of a C-imported type must spell the type the way the compiler
// mangles it. Two layers are pinned here:
//
//   1. The pure rules (`SymbolicDemangler.cImportedTypeIdentity`) over
//      hand-built inputs, one test per rule of the runtime's
//      `_swift_buildDemanglingForContext`.
//   2. The whole path over a dylib compiled on the fly against a bridging
//      header that exercises every import-info shape. Expected manglings are
//      the compiler's own: each literal was read off `_mangledTypeName(T.self)`
//      for the same declarations (Swift 6.2 toolchain, 2026-09-09).

// MARK: - Pure rules

@Suite
struct CImportedTypeIdentityRuleTests {
    private func identifier(_ text: String) -> Node {
        .createTransient(kind: .identifier, text: text)
    }

    private func module(_ text: String) -> Node {
        .createTransient(kind: .module, text: text)
    }

    @Test func tagEnumInTheCModuleManglesAsAStructureEvenWithoutImportInfo() {
        // `typedef NS_ENUM(NSInteger, NSTextAlignment)` carries no import info
        // and mangles as `So15NSTextAlignmentV`.
        let identity = SymbolicDemangler.cImportedTypeIdentity(
            descriptorKind: .enum,
            nameNode: identifier("NSTextAlignment"),
            importInfo: nil,
            isCImportedContext: true
        )
        #expect(identity.kind == .structure)
        #expect(identity.nameNode.text == "NSTextAlignment")
    }

    @Test func swiftEnumKeepsItsKind() {
        let identity = SymbolicDemangler.cImportedTypeIdentity(
            descriptorKind: .enum,
            nameNode: identifier("Direction"),
            importInfo: nil,
            isCImportedContext: false
        )
        #expect(identity.kind == .enum)
    }

    @Test func cTypedefManglesAsATypeAliasUnderItsABIName() {
        // `CGColor` is the `CGColorRef` typedef: `So10CGColorRefa`.
        let identity = SymbolicDemangler.cImportedTypeIdentity(
            descriptorKind: .class,
            nameNode: identifier("CGColor"),
            importInfo: TypeImportInfo(components: ["NCGColorRef", "St"]),
            isCImportedContext: true
        )
        #expect(identity.kind == .typeAlias)
        #expect(identity.nameNode.kind == .identifier)
        #expect(identity.nameNode.text == "CGColorRef")
    }

    @Test func abiNameOverrideAloneKeepsTheDescriptorKind() {
        // `NSRange` is the tag `_NSRange`: `So8_NSRangeV`.
        let identity = SymbolicDemangler.cImportedTypeIdentity(
            descriptorKind: .structure,
            nameNode: identifier("NSRange"),
            importInfo: TypeImportInfo(components: ["N_NSRange"]),
            isCImportedContext: true
        )
        #expect(identity.kind == .structure)
        #expect(identity.nameNode.text == "_NSRange")
    }

    @Test func relatedEntityWrapsTheABINameAndIsNotATagType() {
        // The error struct synthesized for `NS_ERROR_ENUM(CKErrorDomain,
        // CKErrorCode)`: `SC11CKErrorCodeLeV`, printed as
        // `__C_Synthesized.related decl 'e' for CKErrorCode`.
        let identity = SymbolicDemangler.cImportedTypeIdentity(
            descriptorKind: .enum,
            nameNode: identifier("CKError"),
            importInfo: TypeImportInfo(components: ["NCKErrorCode", "Re"]),
            isCImportedContext: true
        )
        // A related entity is exempt from the tag rule, so an enum descriptor
        // would stay an enum; the real synthesized wrapper is a struct.
        #expect(identity.kind == .enum)
        #expect(identity.nameNode.kind == .relatedEntityDeclName)
        #expect(identity.nameNode.children.first?.text == "e")
        #expect(identity.nameNode.children.at(1)?.text == "CKErrorCode")
    }

    @Test func privateDeclarationNameIsNeverOverridden() {
        let privateDeclName = Node.createTransient(kind: .privateDeclName, children: [identifier("33C4A2"), identifier("Hidden")])
        let identity = SymbolicDemangler.cImportedTypeIdentity(
            descriptorKind: .structure,
            nameNode: privateDeclName,
            importInfo: TypeImportInfo(components: ["NSomethingElse"]),
            isCImportedContext: false
        )
        #expect(identity.nameNode.kind == .privateDeclName)
    }

    @Test(arguments: [
        ("__C", true),
        ("__C_Synthesized", true),
        ("Foundation", false),
    ])
    func cImportedContextIsDecidedByTheRootModule(moduleName: String, expected: Bool) {
        let nested = Node.createTransient(kind: .structure, children: [module(moduleName), identifier("Outer")])
        #expect(SymbolicDemangler.isCImportedContext(nested) == expected)
        #expect(SymbolicDemangler.isCImportedContext(module(moduleName)) == expected)
    }

    @Test func missingParentIsNotCImported() {
        #expect(SymbolicDemangler.isCImportedContext(nil) == false)
    }

    @Test func importInfoParsingIgnoresUnknownComponents() {
        let importInfo = TypeImportInfo(components: ["NAbi", "Xfuture", "", "St", "Re"])
        #expect(importInfo.abiName == "Abi")
        #expect(importInfo.symbolNamespace == "t")
        #expect(importInfo.relatedEntityName == "e")
        #expect(importInfo.isCTypedef)
        #expect(importInfo.isRelatedEntity)
    }
}

// MARK: - Whole path over a compiled fixture

/// A dylib whose one struct holds a field of every C-imported shape the
/// import-info rules distinguish. The bridging header declares the
/// header-only shapes; the SDK supplies the typedef, CF and renamed-tag ones.
@Suite
struct CImportedTypeIdentityFixtureTests {
    private enum FixtureWorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in FixtureWorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    private static let fixtureHeader = """
    #import <Foundation/Foundation.h>

    extern NSString *const ProbeErrorDomain;

    typedef NS_ERROR_ENUM(ProbeErrorDomain, ProbeErrorCode) {
        ProbeErrorCodeFirst = 1,
        ProbeErrorCodeSecond = 2,
    };

    typedef NS_ENUM(NSInteger, ProbeMode) { ProbeModeOne, ProbeModeTwo };

    typedef NS_OPTIONS(NSUInteger, ProbeOptions) { ProbeOptionsA = 1, ProbeOptionsB = 2 };

    typedef struct __attribute__((swift_name("ProbePoint"))) ProbeOriginalPoint { double x; double y; } ProbeOriginalPoint;

    typedef struct { int32_t value; } ProbeAnonymousTag;

    typedef NSString *ProbeIdentifier __attribute__((swift_wrapper(struct)));
    """

    /// `Anchor` keeps a `__DATA` segment in the dylib (see AGENTS.md,
    /// "On-the-fly-compiled fixture dylibs need a class").
    private static let fixtureSource = """
    import Foundation
    import CoreGraphics

    public final class Anchor {}

    public struct Holder {
        public var synthesizedError: ProbeError
        public var synthesizedErrorCode: ProbeError.Code
        public var tagEnum: ProbeMode
        public var tagOptions: ProbeOptions
        public var renamedTag: ProbePoint
        public var anonymousTagTypedef: ProbeAnonymousTag
        public var wrapperTypedef: ProbeIdentifier
        public var sdkTypedefStruct: Decimal
        public var sdkCoreFoundationClass: CGColor
        public var sdkRenamedTag: NSRange
    }
    """

    /// Field name, the compiler's mangling of its type, and the runtime's
    /// qualified spelling (`_typeName(_:qualified: true)`).
    private static let expectations: [(fieldName: String, mangling: String, printedName: String)] = [
        ("synthesizedError", "SC14ProbeErrorCodeLeV", "__C_Synthesized.related decl 'e' for ProbeErrorCode"),
        ("synthesizedErrorCode", "So14ProbeErrorCodeV", "__C.ProbeErrorCode"),
        ("tagEnum", "So9ProbeModeV", "__C.ProbeMode"),
        ("tagOptions", "So12ProbeOptionsV", "__C.ProbeOptions"),
        ("renamedTag", "So18ProbeOriginalPointV", "__C.ProbeOriginalPoint"),
        ("anonymousTagTypedef", "So17ProbeAnonymousTaga", "__C.ProbeAnonymousTag"),
        ("wrapperTypedef", "So15ProbeIdentifiera", "__C.ProbeIdentifier"),
        ("sdkTypedefStruct", "So9NSDecimala", "__C.NSDecimal"),
        ("sdkCoreFoundationClass", "So10CGColorRefa", "__C.CGColorRef"),
        ("sdkRenamedTag", "So8_NSRangeV", "__C._NSRange"),
    ]

    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CImportedTypeIdentityFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let headerURL = workingDirectory.appendingPathComponent("CImportedTypeIdentityFixture.h")
            let sourceURL = workingDirectory.appendingPathComponent("CImportedTypeIdentityFixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("libCImportedTypeIdentityFixture.dylib")
            try fixtureHeader.write(to: headerURL, atomically: true, encoding: .utf8)
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-emit-library", "-module-name", "CImportedTypeIdentityFixture",
                "-target", "arm64-apple-macosx15.0",
                "-import-objc-header", headerURL.path,
                // `ProbeErrorDomain` is declared but defined nowhere; the
                // synthesized error struct references it, so let the link
                // resolve it lazily like a real framework's client would.
                "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain BEFORE waitUntilExit — see LegacyDyldInfoBindTests.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    private struct FixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "C-imported-type-identity fixture compilation failed:\n\(diagnostics)" }
    }

    private func loadFixtureMachOFile() throws -> MachOFile {
        let libraryURL = try Self.fixtureCompilationResult.get()
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    private func holderFieldMangledTypeNames(in machOFile: MachOFile) throws -> [String: MangledName] {
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .struct(let structDescriptor) = typeContextDescriptor else { continue }
            guard try structDescriptor.name(in: machOFile) == "Holder" else { continue }
            let fieldDescriptor = try #require(try structDescriptor.fieldDescriptor(in: machOFile))
            var mangledTypeNamesByFieldName: [String: MangledName] = [:]
            for record in try fieldDescriptor.records(in: machOFile) {
                mangledTypeNamesByFieldName[try record.fieldName(in: machOFile)] = try record.mangledTypeName(in: machOFile)
            }
            return mangledTypeNamesByFieldName
        }
        throw FixtureCompilationError(diagnostics: "fixture is missing the struct Holder")
    }

    /// The premise every assertion below stands on: the field's mangled type
    /// name reaches its type through a context-descriptor symbolic reference
    /// (`\x01` direct or `\x02` indirect), so the descriptor-derived path is
    /// what produces the tree. A plain mangled string would bypass it and
    /// prove nothing.
    private func contextReferenceCount(in mangledName: MangledName) -> Int {
        mangledName.lookupElements.filter { element in
            guard case .relative(let reference) = element.reference else { return false }
            return reference.kind == 0x01 || reference.kind == 0x02
        }.count
    }

    /// Strips the `$s` the remangler puts in front of a type mangling so the
    /// result compares against `_mangledTypeName`'s prefix-less spelling.
    private func typeMangling(of node: Node) throws -> String {
        let mangled = try mangleAsString(node)
        return mangled.hasPrefix("$s") ? String(mangled.dropFirst(2)) : mangled
    }

    @Test func everyFieldReachesItsTypeThroughAContextReference() throws {
        let machOFile = try loadFixtureMachOFile()
        let mangledTypeNames = try holderFieldMangledTypeNames(in: machOFile)
        for expectation in Self.expectations {
            let mangledTypeName = try #require(mangledTypeNames[expectation.fieldName], "Holder has no field \(expectation.fieldName)")
            #expect(contextReferenceCount(in: mangledTypeName) == 1, "\(expectation.fieldName) is not a symbolic reference")
        }
    }

    @Test func descriptorDerivedTreesMangleTheWayTheCompilerDoes() throws {
        let machOFile = try loadFixtureMachOFile()
        let mangledTypeNames = try holderFieldMangledTypeNames(in: machOFile)
        for expectation in Self.expectations {
            let mangledTypeName = try #require(mangledTypeNames[expectation.fieldName], "Holder has no field \(expectation.fieldName)")
            let node = try SymbolicDemangler.demangleType(for: mangledTypeName, in: machOFile)
            #expect(try typeMangling(of: node) == expectation.mangling, Comment(rawValue: expectation.fieldName))
        }
    }

    @Test func descriptorDerivedTreesPrintTheRuntimeSpelling() throws {
        let machOFile = try loadFixtureMachOFile()
        let mangledTypeNames = try holderFieldMangledTypeNames(in: machOFile)
        for expectation in Self.expectations {
            let mangledTypeName = try #require(mangledTypeNames[expectation.fieldName], "Holder has no field \(expectation.fieldName)")
            let node = try SymbolicDemangler.demangleType(for: mangledTypeName, in: machOFile)
            #expect(node.print(using: .default) == expectation.printedName, Comment(rawValue: expectation.fieldName))
        }
    }

    /// The import info itself, read straight off the descriptors the
    /// references point at.
    @Test func importInfoComponentsAreReadOffTheDescriptors() throws {
        let machOFile = try loadFixtureMachOFile()
        var importInfosByUserFacingName: [String: TypeImportInfo?] = [:]
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            let descriptor = typeContextDescriptor.contextDescriptor
            guard try descriptor.isCImportedContextDescriptor(in: machOFile) else { continue }
            let typeDescriptor = try #require(typeContextDescriptor.contextDescriptor as? any TypeContextDescriptorProtocol)
            importInfosByUserFacingName[try typeDescriptor.name(in: machOFile)] = try typeDescriptor.typeImportInfo(in: machOFile)
        }
        #expect(importInfosByUserFacingName["ProbeMode"] == .some(nil))
        #expect(importInfosByUserFacingName["ProbePoint"] == TypeImportInfo(abiName: "ProbeOriginalPoint", symbolNamespace: nil, relatedEntityName: nil))
        #expect(importInfosByUserFacingName["ProbeAnonymousTag"] == TypeImportInfo(abiName: nil, symbolNamespace: "t", relatedEntityName: nil))
        #expect(importInfosByUserFacingName["ProbeError"] == TypeImportInfo(abiName: "ProbeErrorCode", symbolNamespace: nil, relatedEntityName: "e"))
        #expect(importInfosByUserFacingName["CGColor"] == TypeImportInfo(abiName: "CGColorRef", symbolNamespace: "t", relatedEntityName: nil))
        // `NSRange` is absent on purpose: Foundation's overlay owns that
        // descriptor, so the fixture reaches it through a bind symbol
        // (`$sSo8_NSRangeVMn`) and emits no copy of its own. Its spelling is
        // still pinned by the mangling test above, via the symbol path.
    }
}
