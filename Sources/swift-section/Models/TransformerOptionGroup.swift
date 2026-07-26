import ArgumentParser
import Foundation
import OutputTransformer
import SwiftDeclarationRendering
import SwiftPrinting

extension Transformer.SwiftEnumLayout.Preset: ExpressibleByArgument {}

// MARK: - Option Group

/// The comment-template options shared by every command that renders Swift
/// declarations (`dump`, `interface`, and the `transformer config` helper).
///
/// Three layers, each overriding the previous one:
///
/// 1. `--transformer-config` — a JSON file decoded straight into a
///    `Transformer.SwiftConfiguration` (the same shape RuntimeViewer persists,
///    so a configuration tuned in its settings UI can be reused verbatim).
/// 2. `--enum-layout-style` — a whole-module preset for the enum-layout module.
/// 3. The per-module template / formatting options — one field each.
///
/// A module that ends up enabled also turns on the comment kind it renders (see
/// ``commentFlagsForEnabledModules(of:)``), so passing a template is enough to
/// see its output — no separate `--emit-…` flag to remember.
struct TransformerOptionGroup: ParsableArguments, Sendable {
    private static let templateValueHelp = "Pass a built-in template name (list them with `swift-section transformer templates`) or a literal template containing ${token} placeholders (list them with `swift-section transformer tokens`)."

    @Option(
        name: .customLong("transformer-config"),
        help: "Path to a JSON file describing the comment transformer configuration. Accepts the same shape RuntimeViewer persists; keys of the ObjC-side modules are ignored.",
        completion: .file()
    )
    var transformerConfigurationPath: String?

    @Option(help: "The comment style for enum layout comments: detailed (byte masks), explained (bit ranges in plain words), standard (no per-byte lines), inline (one line per case with the byte summary), or compact (one line per case).")
    var enumLayoutStyle: Transformer.SwiftEnumLayout.Preset?

    // MARK: Field Offset

    @Option(help: ArgumentHelp("Template for field offset comments. \(templateValueHelp)", valueName: "template"))
    var fieldOffsetTemplate: String?

    @Flag(inversion: .prefixedNo, help: "Render field offset numbers as hexadecimal.")
    var fieldOffsetHex: Bool?

    // MARK: VTable Offset

    @Option(help: ArgumentHelp("Template for vtable offset comments. \(templateValueHelp)", valueName: "template"))
    var vtableOffsetTemplate: String?

    @Option(help: ArgumentHelp("Template for vtable offset comments carrying a label (getter/setter). \(templateValueHelp)", valueName: "template"))
    var vtableOffsetLabeledTemplate: String?

    @Flag(inversion: .prefixedNo, help: "Render vtable offset numbers as hexadecimal.")
    var vtableOffsetHex: Bool?

    // MARK: Member Address

    @Option(help: ArgumentHelp("Template for member address comments. \(templateValueHelp)", valueName: "template"))
    var memberAddressTemplate: String?

    @Flag(inversion: .prefixedNo, help: "Render member addresses as hexadecimal.")
    var memberAddressHex: Bool?

    // MARK: Type Layout

    @Option(help: ArgumentHelp("Template for type layout comments. \(templateValueHelp)", valueName: "template"))
    var typeLayoutTemplate: String?

    @Flag(inversion: .prefixedNo, help: "Render type layout numbers as hexadecimal.")
    var typeLayoutHex: Bool?

    // MARK: Enum Layout

    @Option(help: ArgumentHelp("Template for the enum layout strategy line. \(templateValueHelp)", valueName: "template"))
    var enumLayoutTemplate: String?

    @Option(help: ArgumentHelp("Template for each enum layout case block. \(templateValueHelp)", valueName: "template"))
    var enumLayoutCaseTemplate: String?

    @Option(help: ArgumentHelp("Template for each fixed-byte line of an enum layout case. \(templateValueHelp)", valueName: "template"))
    var enumLayoutByteTemplate: String?

    @Flag(inversion: .prefixedNo, help: "Render enum layout numbers as hexadecimal.")
    var enumLayoutHex: Bool?

    @Flag(inversion: .prefixedNo, help: "Append the pattern note and fixed-byte lines after a case template that does not reference them itself.")
    var enumLayoutAppendOmittedDetails: Bool?

    /// The configuration described by these options, or `nil` when none of them
    /// was given — in which case the caller leaves its render configuration
    /// untouched and the library's built-in comment rendering applies.
    func buildTransformerConfiguration() throws -> Transformer.SwiftConfiguration? {
        var configuration = try loadBaseConfiguration()
        var hasAnyOption = transformerConfigurationPath != nil

        if let enumLayoutStyle {
            configuration.swiftEnumLayout = enumLayoutStyle.module
            hasAnyOption = true
        }

        if let fieldOffsetTemplate {
            configuration.swiftFieldOffset.template = try TransformerTemplateResolver.resolve(
                fieldOffsetTemplate,
                among: Transformer.SwiftFieldOffset.Templates.all,
                optionName: "--field-offset-template"
            )
            configuration.swiftFieldOffset.isEnabled = true
            hasAnyOption = true
        }
        if let fieldOffsetHex {
            configuration.swiftFieldOffset.useHexadecimal = fieldOffsetHex
            configuration.swiftFieldOffset.isEnabled = true
            hasAnyOption = true
        }

        if let vtableOffsetTemplate {
            configuration.swiftVTableOffset.template = try TransformerTemplateResolver.resolve(
                vtableOffsetTemplate,
                among: Transformer.SwiftVTableOffset.Templates.all,
                optionName: "--vtable-offset-template"
            )
            configuration.swiftVTableOffset.isEnabled = true
            hasAnyOption = true
        }
        if let vtableOffsetLabeledTemplate {
            configuration.swiftVTableOffset.labeledTemplate = try TransformerTemplateResolver.resolve(
                vtableOffsetLabeledTemplate,
                among: Transformer.SwiftVTableOffset.Templates.allLabeled,
                optionName: "--vtable-offset-labeled-template"
            )
            configuration.swiftVTableOffset.isEnabled = true
            hasAnyOption = true
        }
        if let vtableOffsetHex {
            configuration.swiftVTableOffset.useHexadecimal = vtableOffsetHex
            configuration.swiftVTableOffset.isEnabled = true
            hasAnyOption = true
        }

        if let memberAddressTemplate {
            configuration.swiftMemberAddress.template = try TransformerTemplateResolver.resolve(
                memberAddressTemplate,
                among: Transformer.SwiftMemberAddress.Templates.all,
                optionName: "--member-address-template"
            )
            configuration.swiftMemberAddress.isEnabled = true
            hasAnyOption = true
        }
        if let memberAddressHex {
            configuration.swiftMemberAddress.useHexadecimal = memberAddressHex
            configuration.swiftMemberAddress.isEnabled = true
            hasAnyOption = true
        }

        if let typeLayoutTemplate {
            configuration.swiftTypeLayout.template = try TransformerTemplateResolver.resolve(
                typeLayoutTemplate,
                among: Transformer.SwiftTypeLayout.Templates.all,
                optionName: "--type-layout-template"
            )
            configuration.swiftTypeLayout.isEnabled = true
            hasAnyOption = true
        }
        if let typeLayoutHex {
            configuration.swiftTypeLayout.useHexadecimal = typeLayoutHex
            configuration.swiftTypeLayout.isEnabled = true
            hasAnyOption = true
        }

        if let enumLayoutTemplate {
            configuration.swiftEnumLayout.template = try TransformerTemplateResolver.resolve(
                enumLayoutTemplate,
                among: Transformer.SwiftEnumLayout.Templates.all,
                optionName: "--enum-layout-template"
            )
            configuration.swiftEnumLayout.isEnabled = true
            hasAnyOption = true
        }
        if let enumLayoutCaseTemplate {
            configuration.swiftEnumLayout.caseTemplate = try TransformerTemplateResolver.resolve(
                enumLayoutCaseTemplate,
                among: Transformer.SwiftEnumLayout.CaseTemplates.all,
                optionName: "--enum-layout-case-template"
            )
            configuration.swiftEnumLayout.isEnabled = true
            hasAnyOption = true
        }
        if let enumLayoutByteTemplate {
            configuration.swiftEnumLayout.memoryOffsetTemplate = try TransformerTemplateResolver.resolve(
                enumLayoutByteTemplate,
                among: Transformer.SwiftEnumLayout.MemoryOffsetTemplates.all,
                optionName: "--enum-layout-byte-template"
            )
            configuration.swiftEnumLayout.isEnabled = true
            hasAnyOption = true
        }
        if let enumLayoutHex {
            configuration.swiftEnumLayout.useHexadecimal = enumLayoutHex
            configuration.swiftEnumLayout.isEnabled = true
            hasAnyOption = true
        }
        if let enumLayoutAppendOmittedDetails {
            configuration.swiftEnumLayout.appendsOmittedDetails = enumLayoutAppendOmittedDetails
            configuration.swiftEnumLayout.isEnabled = true
            hasAnyOption = true
        }

        return hasAnyOption ? configuration : nil
    }

    private func loadBaseConfiguration() throws -> Transformer.SwiftConfiguration {
        guard let transformerConfigurationPath else { return .init() }
        let configurationURL = URL(fileURLWithPath: transformerConfigurationPath)
        let configurationData: Data
        do {
            configurationData = try Data(contentsOf: configurationURL)
        } catch {
            throw ValidationError("Cannot read the transformer configuration at '\(transformerConfigurationPath)': \(error.localizedDescription)")
        }
        do {
            return try JSONDecoder().decode(Transformer.SwiftConfiguration.self, from: configurationData)
        } catch {
            throw ValidationError("Cannot decode '\(transformerConfigurationPath)' as a transformer configuration: \(error.localizedDescription)")
        }
    }
}

// MARK: - Template Resolution

/// Resolves a command-line template value: either the name of a built-in
/// template, or a literal template carrying `${token}` placeholders.
enum TransformerTemplateResolver {
    /// A value containing a placeholder is taken literally; otherwise it must
    /// name one of `namedTemplates` (compared with spaces, hyphens, underscores
    /// and letter case ignored). An unrecognized name is an error rather than a
    /// literal template — a template with no placeholder renders a constant
    /// comment, which is never what a misspelled name was meant to produce.
    static func resolve(
        _ value: String,
        among namedTemplates: [(name: String, template: String)],
        optionName: String
    ) throws -> String {
        guard !value.contains("${") else { return value }
        let normalizedValue = normalize(value)
        if let matchedTemplate = namedTemplates.first(where: { normalize($0.name) == normalizedValue }) {
            return matchedTemplate.template
        }
        let availableNames = namedTemplates.map { "'\($0.name)'" }.joined(separator: ", ")
        throw ValidationError(
            """
            '\(value)' is not a built-in template name for \(optionName), and contains no ${token} placeholder to be used as a literal template.
            Available names: \(availableNames).
            """
        )
    }

    private static func normalize(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }
}

// MARK: - Comment Flags

extension Transformer.SwiftConfiguration {
    /// The comment kinds the enabled modules render. A module is only reached
    /// once its comment kind is emitted, so enabling one implies emitting it.
    struct CommentFlags {
        var printFieldOffset = false
        var printVTableOffset = false
        var printMemberAddress = false
        var printTypeLayout = false
        var printEnumLayout = false
    }

    var commentFlagsForEnabledModules: CommentFlags {
        .init(
            printFieldOffset: swiftFieldOffset.isEnabled,
            printVTableOffset: swiftVTableOffset.isEnabled,
            printMemberAddress: swiftMemberAddress.isEnabled,
            printTypeLayout: swiftTypeLayout.isEnabled,
            printEnumLayout: swiftEnumLayout.isEnabled
        )
    }
}

extension DeclarationRenderConfiguration {
    /// Applies `transformers` and turns on the comment kinds its enabled
    /// modules render, leaving every already-requested comment kind on.
    mutating func applyTransformersEnablingCommentKinds(_ transformers: Transformer.SwiftConfiguration) {
        let commentFlags = transformers.commentFlagsForEnabledModules
        printFieldOffset = printFieldOffset || commentFlags.printFieldOffset
        printVTableOffset = printVTableOffset || commentFlags.printVTableOffset
        printMemberAddress = printMemberAddress || commentFlags.printMemberAddress
        printTypeLayout = printTypeLayout || commentFlags.printTypeLayout
        printEnumLayout = printEnumLayout || commentFlags.printEnumLayout
        applyTransformers(transformers)
    }
}

extension SwiftDeclarationPrintConfiguration {
    /// Applies `transformers` and turns on the comment kinds its enabled
    /// modules render, leaving every already-requested comment kind on.
    mutating func applyTransformersEnablingCommentKinds(_ transformers: Transformer.SwiftConfiguration) {
        let commentFlags = transformers.commentFlagsForEnabledModules
        printFieldOffset = printFieldOffset || commentFlags.printFieldOffset
        printVTableOffset = printVTableOffset || commentFlags.printVTableOffset
        printMemberAddress = printMemberAddress || commentFlags.printMemberAddress
        printTypeLayout = printTypeLayout || commentFlags.printTypeLayout
        printEnumLayout = printEnumLayout || commentFlags.printEnumLayout
        applyTransformers(transformers)
    }
}
