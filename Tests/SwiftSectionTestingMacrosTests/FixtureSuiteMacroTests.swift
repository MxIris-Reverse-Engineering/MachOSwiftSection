import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
@testable import SwiftSectionTestingMacros

/// Expansions of `@FixtureSuite`.
@Suite
struct FixtureSuiteMacroTests {
    private static let macroSpecs: [String: MacroSpec] = [
        "FixtureSuite": MacroSpec(type: FixtureSuiteMacro.self, conformances: ["FixtureSuite"]),
    ]

    private static func assertExpansion(
        _ originalSource: String,
        expandedSource: String,
        diagnostics: [DiagnosticSpec] = [],
        applyFixIts: [String]? = nil,
        fixedSource: String? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        assertMacroExpansion(
            originalSource,
            expandedSource: expandedSource,
            diagnostics: diagnostics,
            macroSpecs: macroSpecs,
            applyFixIts: applyFixIts,
            fixedSource: fixedSource,
            failureHandler: { failure in
                Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
            }
        )
    }

    @Test func defaultsTakeTheTestedTypeAndBaselineFromTheClassName() {
        Self.assertExpansion(
            """
            @FixtureSuite
            final class StructDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
            }
            """,
            expandedSource: """
            final class StructDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

                static let testedTypeName: Swift.String = "StructDescriptor"

                static var registeredTestMethodNames: Swift.Set<Swift.String> {
                    StructDescriptorBaseline.registeredTestMethodNames
                }
            }

            extension StructDescriptorTests: FixtureSuite {
            }
            """
        )
    }

    @Test func anExplicitTestedTypeNameKeepsTheBaselineFromTheClassName() {
        Self.assertExpansion(
            """
            @FixtureSuite(testedTypeName: "EnumTagCounts")
            final class EnumFunctionsTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
            }
            """,
            expandedSource: """
            final class EnumFunctionsTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

                static let testedTypeName: Swift.String = "EnumTagCounts"

                static var registeredTestMethodNames: Swift.Set<Swift.String> {
                    EnumFunctionsBaseline.registeredTestMethodNames
                }
            }

            extension EnumFunctionsTests: FixtureSuite {
            }
            """
        )
    }

    @Test func anExplicitBaselineIsUsedAsWritten() {
        Self.assertExpansion(
            """
            @FixtureSuite(testedTypeName: "OpaqueType", baseline: OpaqueTypeBaseline.self)
            final class OpaqueTypeFixtureTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
            }
            """,
            expandedSource: """
            final class OpaqueTypeFixtureTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

                static let testedTypeName: Swift.String = "OpaqueType"

                static var registeredTestMethodNames: Swift.Set<Swift.String> {
                    OpaqueTypeBaseline.registeredTestMethodNames
                }
            }

            extension OpaqueTypeFixtureTests: FixtureSuite {
            }
            """
        )
    }

    @Test func aClassNameWithoutTestsAsksForTheTestedTypeName() {
        Self.assertExpansion(
            """
            @FixtureSuite
            final class StructDescriptorChecks: MachOSwiftSectionFixtureTests {
            }
            """,
            expandedSource: """
            final class StructDescriptorChecks: MachOSwiftSectionFixtureTests {
            }

            extension StructDescriptorChecks: FixtureSuite {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'StructDescriptorChecks' does not end with 'Tests'; name the tested type and the baseline",
                    line: 1,
                    column: 1,
                    fixIts: [FixItSpec(message: "Name the tested type and the baseline")]
                ),
            ],
            applyFixIts: ["Name the tested type and the baseline"],
            fixedSource: """
            @FixtureSuite(testedTypeName: "StructDescriptorChecks", baseline: StructDescriptorChecksBaseline.self)
            final class StructDescriptorChecks: MachOSwiftSectionFixtureTests {
            }
            """
        )
    }

    @Test func aNonLiteralArgumentIsRejected() {
        Self.assertExpansion(
            """
            @FixtureSuite(testedTypeName: name)
            final class StructDescriptorTests: MachOSwiftSectionFixtureTests {
            }
            """,
            expandedSource: """
            final class StructDescriptorTests: MachOSwiftSectionFixtureTests {
            }

            extension StructDescriptorTests: FixtureSuite {
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "testedTypeName: must be a string literal without interpolation", line: 1, column: 31),
            ]
        )
        Self.assertExpansion(
            """
            @FixtureSuite(baseline: baselineType)
            final class StructDescriptorTests: MachOSwiftSectionFixtureTests {
            }
            """,
            expandedSource: """
            final class StructDescriptorTests: MachOSwiftSectionFixtureTests {
            }

            extension StructDescriptorTests: FixtureSuite {
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "baseline: must be a type literal such as SomeBaseline.self", line: 1, column: 25),
            ]
        )
    }

    @Test func theMacroAppliesOnlyToAClass() {
        Self.assertExpansion(
            """
            @FixtureSuite
            struct StructDescriptorTests {
            }
            """,
            expandedSource: """
            struct StructDescriptorTests {
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@FixtureSuite applies to a fixture suite class", line: 1, column: 1),
            ]
        )
    }
}
