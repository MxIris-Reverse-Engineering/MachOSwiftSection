import Foundation
import Testing
import ArgumentParser
import OutputTransformer
import SwiftOutputTransformer
import SwiftDeclarationRendering
import SwiftPrinting
@testable import swift_section

/// Unit tests for the `swift-section` comment-template command-line surface:
/// how a template value resolves (built-in name vs literal template), how the
/// three option layers compose into a `Transformer.SwiftConfiguration`, and how
/// an enabled module turns on the comment kind it renders.
@Suite
struct TransformerOptionGroupTests {

    // MARK: - Template resolution

    @Test func resolvesBuiltInTemplateByName() throws {
        let resolved = try TransformerTemplateResolver.resolve(
            "Range",
            among: Transformer.SwiftFieldOffset.Templates.all,
            optionName: "--field-offset-template"
        )
        #expect(resolved == Transformer.SwiftFieldOffset.Templates.range)
    }

    @Test func templateNameIgnoresCaseSpacesHyphensAndUnderscores() throws {
        let expected = Transformer.SwiftFieldOffset.Templates.startOnly
        for spelling in ["Start Only", "start-only", "startOnly", "START_ONLY", "startonly"] {
            let resolved = try TransformerTemplateResolver.resolve(
                spelling,
                among: Transformer.SwiftFieldOffset.Templates.all,
                optionName: "--field-offset-template"
            )
            #expect(resolved == expected, "spelling '\(spelling)' should resolve to the Start Only template")
        }
    }

    @Test func valueWithPlaceholderIsTakenLiterally() throws {
        let literalTemplate = "at ${startOffset} (Range)"
        let resolved = try TransformerTemplateResolver.resolve(
            literalTemplate,
            among: Transformer.SwiftFieldOffset.Templates.all,
            optionName: "--field-offset-template"
        )
        #expect(resolved == literalTemplate)
    }

    @Test func unknownNameWithoutPlaceholderIsRejected() {
        #expect(throws: (any Error).self) {
            try TransformerTemplateResolver.resolve(
                "rnge",
                among: Transformer.SwiftFieldOffset.Templates.all,
                optionName: "--field-offset-template"
            )
        }
    }

    // MARK: - Configuration building

    @Test func noOptionYieldsNoConfiguration() throws {
        let optionGroup = try TransformerOptionGroup.parse([])
        #expect(try optionGroup.buildTransformerConfiguration() == nil)
    }

    @Test func templateOptionEnablesOnlyItsOwnModule() throws {
        let optionGroup = try TransformerOptionGroup.parse(["--field-offset-template", "range"])
        let configuration = try #require(try optionGroup.buildTransformerConfiguration())
        #expect(configuration.swiftFieldOffset.isEnabled)
        #expect(configuration.swiftFieldOffset.template == Transformer.SwiftFieldOffset.Templates.range)
        #expect(!configuration.swiftVTableOffset.isEnabled)
        #expect(!configuration.swiftMemberAddress.isEnabled)
        #expect(!configuration.swiftTypeLayout.isEnabled)
        #expect(!configuration.swiftEnumLayout.isEnabled)
    }

    @Test func hexadecimalFlagAloneEnablesItsModule() throws {
        let optionGroup = try TransformerOptionGroup.parse(["--no-type-layout-hex"])
        let configuration = try #require(try optionGroup.buildTransformerConfiguration())
        #expect(configuration.swiftTypeLayout.isEnabled)
        #expect(!configuration.swiftTypeLayout.useHexadecimal)
    }

    @Test func enumLayoutStyleInstallsThePreset() throws {
        let optionGroup = try TransformerOptionGroup.parse(["--enum-layout-style", "compact"])
        let configuration = try #require(try optionGroup.buildTransformerConfiguration())
        #expect(configuration.swiftEnumLayout == Transformer.SwiftEnumLayout.compact)
    }

    @Test func perModuleOptionOverridesThePreset() throws {
        let optionGroup = try TransformerOptionGroup.parse([
            "--enum-layout-style", "compact",
            "--enum-layout-template", "verbose",
        ])
        let configuration = try #require(try optionGroup.buildTransformerConfiguration())
        // The preset's case template survives; only the strategy line changes.
        #expect(configuration.swiftEnumLayout.template == Transformer.SwiftEnumLayout.Templates.verbose)
        #expect(configuration.swiftEnumLayout.caseTemplate == Transformer.SwiftEnumLayout.CaseTemplates.compactLine)
    }

    @Test func allFiveModulesAreReachable() throws {
        let optionGroup = try TransformerOptionGroup.parse([
            "--field-offset-template", "range",
            "--vtable-offset-template", "compact",
            "--vtable-offset-labeled-template", "compact",
            "--member-address-template", "labeled",
            "--type-layout-template", "compact",
            "--enum-layout-template", "compact",
        ])
        let configuration = try #require(try optionGroup.buildTransformerConfiguration())
        #expect(configuration.swiftFieldOffset.template == Transformer.SwiftFieldOffset.Templates.range)
        #expect(configuration.swiftVTableOffset.template == Transformer.SwiftVTableOffset.Templates.compact)
        #expect(configuration.swiftVTableOffset.labeledTemplate == Transformer.SwiftVTableOffset.Templates.compactLabeled)
        #expect(configuration.swiftMemberAddress.template == Transformer.SwiftMemberAddress.Templates.labeled)
        #expect(configuration.swiftTypeLayout.template == Transformer.SwiftTypeLayout.Templates.compact)
        #expect(configuration.swiftEnumLayout.template == Transformer.SwiftEnumLayout.Templates.compact)
        #expect(configuration.hasEnabledModules)
    }

    // MARK: - Configuration file

    @Test func configurationFileIsLoadedAndOverriddenByOptions() throws {
        var storedConfiguration = Transformer.SwiftConfiguration()
        storedConfiguration.swiftFieldOffset.isEnabled = true
        storedConfiguration.swiftFieldOffset.template = Transformer.SwiftFieldOffset.Templates.interval
        storedConfiguration.swiftMemberAddress.isEnabled = true
        storedConfiguration.swiftMemberAddress.template = Transformer.SwiftMemberAddress.Templates.compact

        let configurationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transformer-configuration-\(UUID().uuidString).json")
        try JSONEncoder().encode(storedConfiguration).write(to: configurationURL)
        defer { try? FileManager.default.removeItem(at: configurationURL) }

        let optionGroup = try TransformerOptionGroup.parse([
            "--transformer-config", configurationURL.path,
            "--field-offset-template", "range",
        ])
        let configuration = try #require(try optionGroup.buildTransformerConfiguration())
        // The option wins over the file for the module it names…
        #expect(configuration.swiftFieldOffset.template == Transformer.SwiftFieldOffset.Templates.range)
        // …and the file's other modules survive untouched.
        #expect(configuration.swiftMemberAddress.isEnabled)
        #expect(configuration.swiftMemberAddress.template == Transformer.SwiftMemberAddress.Templates.compact)
    }

    @Test func unreadableConfigurationFileIsReported() throws {
        let optionGroup = try TransformerOptionGroup.parse([
            "--transformer-config", "/nonexistent/transformer-configuration.json",
        ])
        #expect(throws: (any Error).self) {
            try optionGroup.buildTransformerConfiguration()
        }
    }

    // MARK: - Comment kinds

    @Test func enabledModulesTurnOnTheirCommentKinds() throws {
        let optionGroup = try TransformerOptionGroup.parse([
            "--field-offset-template", "range",
            "--enum-layout-style", "compact",
        ])
        let configuration = try #require(try optionGroup.buildTransformerConfiguration())

        var renderConfiguration = DeclarationRenderConfiguration.demangleOptions(.default)
        renderConfiguration.applyTransformersEnablingCommentKinds(configuration)
        #expect(renderConfiguration.printFieldOffset)
        #expect(renderConfiguration.printEnumLayout)
        #expect(!renderConfiguration.printTypeLayout)
        #expect(renderConfiguration.fieldOffsetTransformer != nil)
        #expect(renderConfiguration.typeLayoutTransformer == nil)

        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.applyTransformersEnablingCommentKinds(configuration)
        #expect(printConfiguration.printFieldOffset)
        #expect(printConfiguration.printEnumLayout)
        #expect(!printConfiguration.printTypeLayout)
    }

    @Test func alreadyRequestedCommentKindsSurviveADisabledModule() throws {
        let optionGroup = try TransformerOptionGroup.parse(["--field-offset-template", "range"])
        let configuration = try #require(try optionGroup.buildTransformerConfiguration())

        var renderConfiguration = DeclarationRenderConfiguration.demangleOptions(.default)
        renderConfiguration.printTypeLayout = true
        renderConfiguration.applyTransformersEnablingCommentKinds(configuration)
        // The type-layout module stays disabled, but the comment kind the user
        // asked for with --emit-type-layout must not be turned back off.
        #expect(renderConfiguration.printTypeLayout)
        #expect(renderConfiguration.typeLayoutTransformer == nil)
    }
}
