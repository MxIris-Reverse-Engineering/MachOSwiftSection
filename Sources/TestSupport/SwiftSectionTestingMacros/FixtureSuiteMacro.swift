import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@FixtureSuite`: the two `FixtureSuite` requirements of a fixture suite
/// class, and its conformance.
///
/// The tested type's name defaults to the class name without its `Tests`
/// suffix, and the baseline to the same stem followed by `Baseline`:
///
///     @FixtureSuite
///     final class StructDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {}
///
/// gets `static let testedTypeName = "StructDescriptor"` and
/// `static var registeredTestMethodNames` returning
/// `StructDescriptorBaseline.registeredTestMethodNames`. Either is named
/// explicitly with a literal: `@FixtureSuite(testedTypeName: "EnumTagCounts")`,
/// `@FixtureSuite(testedTypeName: "OpaqueType", baseline: OpaqueTypeBaseline.self)`.
public struct FixtureSuiteMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let suite = FixtureSuiteDescription(attribute: node, declaration: declaration, context: context) else {
            return []
        }
        return [
            "static let testedTypeName: Swift.String = \(literal: suite.testedTypeName)",
            """
            static var registeredTestMethodNames: Swift.Set<Swift.String> {
                \(raw: suite.baselineTypeName).registeredTestMethodNames
            }
            """,
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // The member role reports a misuse; this role only stays silent.
        guard declaration.is(ClassDeclSyntax.self), !protocols.isEmpty else { return [] }
        let conformances = protocols.map(\.trimmedDescription).joined(separator: ", ")
        return [try ExtensionDeclSyntax("extension \(type.trimmed): \(raw: conformances) {}")]
    }
}

/// What a `@FixtureSuite` attribute and the class it is attached to say.
struct FixtureSuiteDescription {
    static let classNameSuffix = "Tests"

    let testedTypeName: String
    let baselineTypeName: String

    /// `nil` after diagnosing a misuse.
    init?(attribute: AttributeSyntax, declaration: some DeclGroupSyntax, context: some MacroExpansionContext) {
        guard let classDeclaration = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: attribute, message: FixtureSuiteDiagnostic.notAClass))
            return nil
        }
        let className = classDeclaration.name.text
        let stem = className.hasSuffix(Self.classNameSuffix) && className.count > Self.classNameSuffix.count
            ? String(className.dropLast(Self.classNameSuffix.count))
            : nil

        var explicitTestedTypeName: String?
        var explicitBaselineTypeName: String?
        for argument in attribute.arguments?.as(LabeledExprListSyntax.self) ?? [] {
            switch argument.label?.text {
            case "testedTypeName":
                if argument.expression.is(NilLiteralExprSyntax.self) { continue }
                guard let literal = Self.plainStringLiteral(argument.expression) else {
                    context.diagnose(Diagnostic(node: argument.expression, message: FixtureSuiteDiagnostic.testedTypeNameIsNotALiteral))
                    return nil
                }
                explicitTestedTypeName = literal
            case "baseline":
                if argument.expression.is(NilLiteralExprSyntax.self) { continue }
                guard let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                      memberAccess.declName.baseName.tokenKind == .keyword(.self),
                      let base = memberAccess.base else {
                    context.diagnose(Diagnostic(node: argument.expression, message: FixtureSuiteDiagnostic.baselineIsNotATypeLiteral))
                    return nil
                }
                explicitBaselineTypeName = base.trimmedDescription
            default:
                continue
            }
        }

        guard let testedTypeName = explicitTestedTypeName ?? stem,
              let baselineTypeName = explicitBaselineTypeName ?? stem.map({ $0 + "Baseline" }) else {
            var fixed = attribute
            let arguments: LabeledExprListSyntax = [
                LabeledExprSyntax(label: "testedTypeName", expression: StringLiteralExprSyntax(content: explicitTestedTypeName ?? className))
                    .with(\.trailingComma, .commaToken(trailingTrivia: .space)),
                LabeledExprSyntax(label: "baseline", expression: ExprSyntax("\(raw: explicitBaselineTypeName ?? className + "Baseline").self")),
            ]
            fixed.leftParen = .leftParenToken()
            fixed.arguments = .argumentList(arguments)
            fixed.rightParen = .rightParenToken()
            context.diagnose(Diagnostic(
                node: attribute,
                message: FixtureSuiteDiagnostic.classNameHasNoTestsSuffix(className: className),
                fixIt: FixIt(message: FixtureSuiteFixIt.nameTheTestedTypeAndBaseline, changes: [.replace(oldNode: Syntax(attribute), newNode: Syntax(fixed))])
            ))
            return nil
        }
        self.testedTypeName = testedTypeName
        self.baselineTypeName = baselineTypeName
    }

    /// The text of a string literal without interpolation; `nil` for any
    /// other expression.
    private static func plainStringLiteral(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self) else { return nil }
        var text = ""
        for segment in literal.segments {
            guard let plainSegment = segment.as(StringSegmentSyntax.self) else { return nil }
            text += plainSegment.content.text
        }
        return text
    }
}

enum FixtureSuiteDiagnostic: DiagnosticMessage {
    case notAClass
    case testedTypeNameIsNotALiteral
    case baselineIsNotATypeLiteral
    case classNameHasNoTestsSuffix(className: String)

    var message: String {
        switch self {
        case .notAClass:
            "@FixtureSuite applies to a fixture suite class"
        case .testedTypeNameIsNotALiteral:
            "testedTypeName: must be a string literal without interpolation"
        case .baselineIsNotATypeLiteral:
            "baseline: must be a type literal such as SomeBaseline.self"
        case .classNameHasNoTestsSuffix(let className):
            "'\(className)' does not end with 'Tests'; name the tested type and the baseline"
        }
    }

    var diagnosticID: MessageID {
        let identifier = switch self {
        case .notAClass: "notAClass"
        case .testedTypeNameIsNotALiteral: "testedTypeNameIsNotALiteral"
        case .baselineIsNotATypeLiteral: "baselineIsNotATypeLiteral"
        case .classNameHasNoTestsSuffix: "classNameHasNoTestsSuffix"
        }
        return MessageID(domain: "SwiftSectionTestingMacros", id: identifier)
    }

    var severity: DiagnosticSeverity {
        .error
    }
}

enum FixtureSuiteFixIt: FixItMessage {
    case nameTheTestedTypeAndBaseline

    var message: String {
        "Name the tested type and the baseline"
    }

    var fixItID: MessageID {
        MessageID(domain: "SwiftSectionTestingMacros", id: "nameTheTestedTypeAndBaseline")
    }
}
