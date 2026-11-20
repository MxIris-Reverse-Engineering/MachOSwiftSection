import SwiftSectionFixtureSupport

/// Makes a fixture suite class a ``FixtureSuite``: adds `testedTypeName`,
/// `registeredTestMethodNames` and the conformance.
///
/// ```swift
/// @Suite
/// @FixtureSuite
/// final class StructDescriptorTests: MachOSwiftSectionFixtureTests, @unchecked Sendable { … }
/// ```
///
/// The tested type's name defaults to the class name without its `Tests`
/// suffix (`StructDescriptor`), and the baseline whose
/// `registeredTestMethodNames` the suite reports to the same stem followed by
/// `Baseline` (`StructDescriptorBaseline`). Name either when it differs, with
/// a literal:
///
/// ```swift
/// @FixtureSuite(testedTypeName: "EnumTagCounts")
/// @FixtureSuite(testedTypeName: "OpaqueType", baseline: OpaqueTypeBaseline.self)
/// ```
///
/// `SuiteBehaviorScanner` reads the tested type's name from this attribute
/// the same way.
@attached(member, names: named(testedTypeName), named(registeredTestMethodNames))
@attached(extension, conformances: FixtureSuite)
package macro FixtureSuite(testedTypeName: String? = nil, baseline: Any.Type? = nil) = #externalMacro(module: "SwiftSectionTestingMacros", type: "FixtureSuiteMacro")
