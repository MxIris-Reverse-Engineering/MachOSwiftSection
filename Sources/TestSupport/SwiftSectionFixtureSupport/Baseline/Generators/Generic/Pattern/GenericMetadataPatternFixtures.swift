import Foundation
import MachOFoundation
@testable import MachOSwiftSection

/// The three instantiation patterns every pattern baseline generator works
/// from, loaded once so the baselines cannot drift apart.
package struct GenericMetadataPatternFixtures {
    package let valuePattern: GenericValueMetadataPattern
    package let classPattern: GenericClassMetadataPattern
    package let resilientClassPattern: ResilientClassMetadataPattern

    package init(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        valuePattern = try BaselineFixturePicker.genericValueMetadataPattern_structNonRequirement(in: machO)
        classPattern = try BaselineFixturePicker.genericClassMetadataPattern_classNonRequirement(in: machO)
        resilientClassPattern = try BaselineFixturePicker.resilientClassMetadataPattern_resilientChild(in: machO)
    }
}
