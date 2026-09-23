import Testing
import ArgumentParser
import Foundation
import ObjCDeclarationRendering
import ObjCOutputTransformer
@testable import swift_section

/// Option parsing is the CLI's contract with its users: a flag that silently
/// stops reaching the library, or one that lands on the wrong switch, produces
/// a plausible-looking dump that is quietly wrong. These tests pin the wiring
/// from argument to `ObjCGenerationOptions` field.
@Suite("swift-section objc option parsing")
struct ObjCSectionCommandTests {
    // MARK: - Input

    @Test("Parses a plain file path")
    func parsesFilePath() throws {
        let command = try ObjCDumpCommand.parse(["/tmp/Sample.framework/Sample"])
        #expect(command.machOOptions.filePath == "/tmp/Sample.framework/Sample")
        #expect(command.machOOptions.isDyldSharedCache == false)
        #expect(command.machOOptions.architecture == nil)
    }

    @Test("Parses dyld shared cache input")
    func parsesCacheInput() throws {
        let command = try ObjCDumpCommand.parse([
            "/tmp/dyld_shared_cache_arm64e",
            "--dyld-shared-cache",
            "-n", "Foundation",
            "-a", "arm64e",
        ])
        #expect(command.machOOptions.isDyldSharedCache)
        #expect(command.machOOptions.cacheImageName == "Foundation")
        #expect(command.machOOptions.architecture == .arm64e)
    }

    @Test("Parses the system cache flag without a file path")
    func parsesSystemCacheFlag() throws {
        let command = try ObjCDumpCommand.parse(["--uses-system-dyld-shared-cache", "-p", "/usr/lib/libobjc.A.dylib"])
        #expect(command.machOOptions.filePath == nil)
        #expect(command.machOOptions.usesSystemDyldSharedCache)
        #expect(command.machOOptions.cacheImagePath == "/usr/lib/libobjc.A.dylib")
    }

    // MARK: - Sections and Filter

    @Test("Defaults to every section, and parses an explicit comma-separated list")
    func parsesSections() throws {
        #expect(try ObjCDumpCommand.parse(["/tmp/Sample"]).sections == nil)

        let command = try ObjCDumpCommand.parse(["/tmp/Sample", "-s", "classes,protocols"])
        #expect(command.sections?.kinds == [.classes, .protocols])
    }

    /// The regression this option's spelling was changed for: `--sections` used
    /// to consume every following token, so the input path landed in the list
    /// as one more kind and there was no way to write the option before the
    /// path at all.
    @Test("Parses sections written before the input path")
    func parsesSectionsBeforeFilePath() throws {
        let command = try ObjCDumpCommand.parse(["--sections", "classes,protocols", "/tmp/Sample"])
        #expect(command.sections?.kinds == [.classes, .protocols])
        #expect(command.machOOptions.filePath == "/tmp/Sample")
    }

    /// The two-token shape of the old spelling: `protocols` lands in the
    /// positional slot, which `validate()` recognizes as a declaration kind and
    /// reports instead of failing later on a missing file.
    @Test("Rejects space-separated sections, pointing at the comma form")
    func rejectsSpaceSeparatedSections() {
        #expect(throws: (any Error).self) {
            try ObjCDumpCommand.parse(["--sections", "classes", "protocols"])
        }
    }

    @Test("Rejects malformed section lists", arguments: ["classes,", "", "bogus", "classes,bogus", "classes protocols"])
    func rejectsMalformedSections(argument: String) {
        #expect(throws: (any Error).self) {
            try ObjCDumpCommand.parse(["/tmp/Sample", "--sections", argument])
        }
    }

    @Test("Collapses a repeated section so it is not dumped twice")
    func deduplicatesRepeatedSections() throws {
        let command = try ObjCDumpCommand.parse(["/tmp/Sample", "--sections", "classes,protocols,classes"])
        #expect(command.sections?.kinds == [.classes, .protocols])
    }

    /// A path that merely looks like a kind is only an error when `--sections`
    /// is present too — otherwise it is just a file called `classes`.
    @Test("Accepts a kind-shaped path when no sections are requested")
    func acceptsKindShapedPathWithoutSections() throws {
        let command = try ObjCDumpCommand.parse(["classes"])
        #expect(command.machOOptions.filePath == "classes")
    }

    @Test("Parses a name filter")
    func parsesFilter() throws {
        let command = try ObjCDumpCommand.parse(["/tmp/Sample", "--filter", "NSString"])
        #expect(command.filter == "NSString")
    }

    // MARK: - Generation Switches

    @Test("Every generation switch is off by default")
    func generationSwitchesDefaultOff() throws {
        let options = try ObjCDumpCommand.parse(["/tmp/Sample"]).generationOptions.build()
        #expect(options == ObjCGenerationOptions.default)
    }

    @Test("Each generation flag lands on its own switch")
    func generationFlagsMapOntoOptions() throws {
        let command = try ObjCDumpCommand.parse([
            "/tmp/Sample",
            "--strip-protocol-conformance",
            "--strip-overrides",
            "--strip-synthesized-ivars",
            "--strip-synthesized-methods",
            "--strip-ctor-method",
            "--strip-dtor-method",
            "--emit-ivar-offsets",
            "--emit-property-attributes",
            "--emit-method-imp-addresses",
            "--emit-property-accessor-addresses",
        ])
        let options = command.generationOptions.build()

        #expect(options.stripProtocolConformance)
        #expect(options.stripOverrides)
        #expect(options.stripSynthesizedIvars)
        #expect(options.stripSynthesizedMethods)
        #expect(options.stripCtorMethod)
        #expect(options.stripDtorMethod)
        #expect(options.addIvarOffsetComments)
        #expect(options.addPropertyAttributesComments)
        #expect(options.addMethodIMPAddressComments)
        #expect(options.addPropertyAccessorAddressComments)
    }

    @Test("One flag on leaves the other nine off")
    func generationFlagsAreIndependent() throws {
        let options = try ObjCDumpCommand.parse(["/tmp/Sample", "--strip-overrides"]).generationOptions.build()
        #expect(options.stripOverrides)
        #expect(options == ObjCGenerationOptions(stripOverrides: true))
    }

    // MARK: - C Type Replacement

    @Test("Parses repeated C type replacements in either spelling")
    func parsesCTypeReplacements() throws {
        let command = try ObjCDumpCommand.parse([
            "/tmp/Sample",
            "--c-type-replacement", "double=CGFloat",
            "--c-type-replacement", "unsigned long long=NSUInteger",
            "--c-type-replacement", "longLong=NSInteger",
        ])
        let replacements = try command.transformerOptions.buildCTypeReplacements()

        #expect(replacements[.double] == "CGFloat")
        #expect(replacements[.ulongLong] == "NSUInteger")
        #expect(replacements[.longLong] == "NSInteger")
        #expect(replacements.count == 3)
    }

    @Test("An individual replacement overrides the preset it came with")
    func individualReplacementBeatsPreset() throws {
        let command = try ObjCDumpCommand.parse([
            "/tmp/Sample",
            "--c-type-preset", "foundation",
            "--c-type-replacement", "double=double",
        ])
        let replacements = try command.transformerOptions.buildCTypeReplacements()

        #expect(replacements[.double] == "double")
        // The rest of the preset survives.
        #expect(replacements[.long] == "NSInteger")
    }

    @Test("A malformed replacement is rejected rather than ignored")
    func malformedReplacementThrows() throws {
        let command = try ObjCDumpCommand.parse(["/tmp/Sample", "--c-type-replacement", "double"])
        #expect(throws: ObjCSectionCommandError.self) {
            _ = try command.transformerOptions.buildCTypeReplacements()
        }
    }

    @Test("An unknown C type is rejected rather than ignored")
    func unknownCTypeThrows() throws {
        let command = try ObjCDumpCommand.parse(["/tmp/Sample", "--c-type-replacement", "size_t=NSUInteger"])
        #expect(throws: ObjCSectionCommandError.self) {
            _ = try command.transformerOptions.buildCTypeReplacements()
        }
    }

    @Test("No replacement option means an empty table, not a default one")
    func noReplacementsMeansEmptyTable() throws {
        let command = try ObjCDumpCommand.parse(["/tmp/Sample"])
        #expect(try command.transformerOptions.buildCTypeReplacements().isEmpty)
    }

    // MARK: - Ivar Offset Template

    @Test("No template option leaves the renderer's own wording in place")
    func noTemplateMeansNoBuilder() throws {
        let command = try ObjCDumpCommand.parse(["/tmp/Sample"])
        #expect(command.transformerOptions.buildIvarOffsetCommentBuilder() == nil)
        #expect(command.transformerOptions.impliesIvarOffsetComments == false)
    }

    @Test("A template is applied, and switches ivar offset comments on")
    func templateIsAppliedAndImpliesComments() throws {
        let command = try ObjCDumpCommand.parse([
            "/tmp/Sample",
            "--ivar-offset-template", "ivar @ ${offset}",
        ])
        let builder = try #require(command.transformerOptions.buildIvarOffsetCommentBuilder())

        #expect(builder(16) == "ivar @ 0x10")
        #expect(command.transformerOptions.impliesIvarOffsetComments)
    }

    @Test("Decimal formatting is a customization on its own")
    func decimalFlagAloneBuildsABuilder() throws {
        let command = try ObjCDumpCommand.parse(["/tmp/Sample", "--ivar-offset-decimal"])
        let builder = try #require(command.transformerOptions.buildIvarOffsetCommentBuilder())

        #expect(builder(16) == "offset: 16")
        #expect(command.transformerOptions.impliesIvarOffsetComments)
    }

    // MARK: - Interface Subcommand

    @Test("The interface subcommand takes the declaration name first")
    func parsesInterfaceCommand() throws {
        let command = try ObjCInterfaceCommand.parse(["NSString", "/tmp/Sample"])
        #expect(command.declarationName == "NSString")
        #expect(command.machOOptions.filePath == "/tmp/Sample")
        #expect(command.kind == nil)
    }

    @Test("The interface subcommand can be pinned to one kind")
    func parsesInterfaceKind() throws {
        let command = try ObjCInterfaceCommand.parse(["Foo(Bar)", "/tmp/Sample", "--kind", "categories"])
        #expect(command.kind == .categories)
    }

    // MARK: - Command Tree

    @Test("dump is the default objc subcommand")
    func dumpIsDefault() {
        #expect(ObjCCommand.configuration.defaultSubcommand == ObjCDumpCommand.self)
        #expect(ObjCCommand.configuration.commandName == "objc")
    }

    /// The group only exists for users if the root command lists it; a
    /// dropped `ObjCCommand.self` would compile and pass every test above.
    @Test("swift-section objc <file> reaches the ObjC dump")
    func objcGroupIsReachableFromRoot() throws {
        let command = try SwiftSectionCommand.parseAsRoot(["objc", "/tmp/Sample"])
        let dumpCommand = try #require(command as? ObjCDumpCommand)
        #expect(dumpCommand.machOOptions.filePath == "/tmp/Sample")
    }
}
