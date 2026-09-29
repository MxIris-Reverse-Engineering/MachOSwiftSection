import ArgumentParser
import Foundation
import ObjCDeclarationRendering
import ObjCOutputTransformer
import OutputTransformer

/// The two comment/spelling templates the ObjC renderer understands: what to
/// call the C primitive types, and how to word an ivar-offset comment.
///
/// `swift-section` spends a 275-line subcommand on interactively managing its
/// template library. There is no equivalent here on purpose — two modules do
/// not need a management UI, they need two options.
struct ObjCTransformerOptionGroup: ParsableArguments, Sendable {
    @Option(
        name: .customLong("c-type-replacement"),
        parsing: .singleValue,
        help: ArgumentHelp(
            "Replace a C primitive type with another spelling, e.g. double=CGFloat. Repeatable.",
            discussion: "The C type may be spelled either as it appears in source (\"unsigned long long\") or in camel case (ulongLong)."
        )
    )
    var cTypeReplacementArguments: [String] = []

    @Option(help: "Apply a preset set of C type replacements before any individual --c-type-replacement.")
    var cTypePreset: CTypePreset?

    @Option(
        help: ArgumentHelp(
            "Template for the ivar offset comment. Use ${offset} for the value.",
            discussion: "Implies --emit-ivar-offsets. Default: \"offset: ${offset}\"."
        )
    )
    var ivarOffsetTemplate: String?

    @Flag(help: "Print ivar offsets in decimal instead of hexadecimal.")
    var ivarOffsetDecimal: Bool = false

    /// The replacement table the renderer consumes, or an empty table when no
    /// replacement option was given.
    ///
    /// Individual `--c-type-replacement` entries win over `--c-type-preset`, so
    /// a preset can be adopted wholesale and then corrected in one spot.
    func buildCTypeReplacements() throws -> [ObjCPrimitiveTypePattern: String] {
        var replacements: [Transformer.CType.Pattern: String] = cTypePreset?.replacements ?? [:]

        for argument in cTypeReplacementArguments {
            guard let separatorIndex = argument.firstIndex(of: "=") else {
                throw ObjCSectionCommandError.malformedCTypeReplacement(argument)
            }
            let typeName = String(argument[argument.startIndex ..< separatorIndex])
            let replacement = String(argument[argument.index(after: separatorIndex)...])
            guard !typeName.isEmpty, !replacement.isEmpty else {
                throw ObjCSectionCommandError.malformedCTypeReplacement(argument)
            }
            guard let pattern = CTypeName.pattern(for: typeName) else {
                throw ObjCSectionCommandError.unknownCType(typeName)
            }
            replacements[pattern] = replacement
        }

        // The renderer takes its own pattern enum rather than the template
        // engine's, so that library users get C-type substitution without
        // depending on the engine — see `ObjCPrimitiveTypePattern`. The two
        // share raw values, which is where they meet.
        return replacements.reduce(into: [:]) { result, entry in
            if let renderingPattern = ObjCPrimitiveTypePattern(rawValue: entry.key.rawValue) {
                result[renderingPattern] = entry.value
            }
        }
    }

    /// The ivar-offset comment builder, or `nil` to keep the renderer's
    /// built-in wording.
    func buildIvarOffsetCommentBuilder() -> (@Sendable (Int) -> String)? {
        // Hexadecimal is the module's own default, so asking for decimal is a
        // customization even without a template.
        guard ivarOffsetTemplate != nil || ivarOffsetDecimal else { return nil }
        let module = Transformer.ObjCIvarOffset(
            isEnabled: true,
            template: ivarOffsetTemplate ?? Transformer.ObjCIvarOffset.Templates.standard,
            useHexadecimal: !ivarOffsetDecimal
        )
        return { offset in module.transform(.init(offset: offset)) }
    }

    /// Whether a template option was given that only has an effect once ivar
    /// offset comments are switched on.
    var impliesIvarOffsetComments: Bool {
        ivarOffsetTemplate != nil || ivarOffsetDecimal
    }
}

/// Named bundles of C type replacements, mirroring
/// `Transformer.CType.Presets`.
enum CTypePreset: String, CaseIterable, ExpressibleByArgument, Sendable {
    case stdint
    case foundation
    case mixed

    var replacements: [Transformer.CType.Pattern: String] {
        switch self {
        case .stdint: Transformer.CType.Presets.stdint
        case .foundation: Transformer.CType.Presets.foundation
        case .mixed: Transformer.CType.Presets.mixed
        }
    }
}

/// Maps the command-line spelling of a C type onto a replacement pattern.
///
/// Both spellings are accepted: the source form (`unsigned long long`, which
/// needs quoting in a shell) and the camel-case form (`ulongLong`, which does
/// not).
enum CTypeName {
    static func pattern(for spelling: String) -> Transformer.CType.Pattern? {
        let normalized = spelling.trimmingCharacters(in: .whitespaces)
        if let pattern = Transformer.CType.Pattern(rawValue: normalized) {
            return pattern
        }
        return Transformer.CType.Pattern.allCases.first { $0.displayName == normalized }
    }

    static var allSpellings: [String] {
        Transformer.CType.Pattern.allCases.map(\.rawValue)
    }
}
