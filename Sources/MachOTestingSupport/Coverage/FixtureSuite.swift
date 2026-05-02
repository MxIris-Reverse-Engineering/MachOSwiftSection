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
package protocol FixtureSuite {
    static var testedTypeName: String { get }
    static var registeredTestMethodNames: Set<String> { get }
}
