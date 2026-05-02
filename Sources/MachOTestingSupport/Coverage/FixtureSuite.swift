import Foundation

/// Conformance contract for fixture-based test suites participating in coverage tracking.
///
/// Each Suite type provides:
/// - `testedTypeName`: the source-code Type whose public members the Suite covers
///   (e.g. "StructDescriptor"). Must match the type name exactly as it appears in
///   `Sources/MachOSwiftSection/Models/`.
/// - `registeredTestMethodNames`: the member names covered by `@Test` methods in this Suite.
///   For each entry "foo", the Coverage Invariant test expects a public member
///   `<testedTypeName>.foo` (any overload group) to exist in the source.
///
/// **Actor isolation:** This protocol is `@MainActor`-isolated because all current
/// conformers inherit from `MachOSwiftSectionFixtureTests`, which is `@MainActor`.
/// Code iterating `[any FixtureSuite.Type]` (e.g., the Coverage Invariant Test in
/// Task 16) must run on the main actor too.
///
/// **Suite inclusion rule:** Every Swift file under `Sources/MachOSwiftSection/Models/`
/// gets a corresponding `<File>Tests.swift` Suite UNLESS:
/// - The file declares only `*Layout` types (covered by LayoutTests).
/// - The file declares only enums/flags/protocols with no public func/var/init.
/// - The file is excluded via `CoverageAllowlistEntries.swift` with a documented reason.
///
/// The Coverage Invariant Test (Task 16) catches drift between source and Suites.
@MainActor
package protocol FixtureSuite {
    static var testedTypeName: String { get }
    static var registeredTestMethodNames: Set<String> { get }
}
