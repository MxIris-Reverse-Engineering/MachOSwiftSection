import Foundation
import MachOFoundation
@testable import MachOSwiftSection

/// The four property descriptors every key path baseline generator works
/// from, loaded once so the four baselines cannot drift apart.
package struct KeyPathFixtureDescriptors {
    package let trivial: PropertyDescriptor
    package let inlineStoredOffset: PropertyDescriptor
    package let unresolvedFieldOffset: PropertyDescriptor
    package let computedSettable: PropertyDescriptor

    package init(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        trivial = try BaselineFixturePicker.propertyDescriptor_trivial(in: machO)
        inlineStoredOffset = try BaselineFixturePicker.propertyDescriptor_inlineStoredOffset(in: machO)
        unresolvedFieldOffset = try BaselineFixturePicker.propertyDescriptor_unresolvedFieldOffset(in: machO)
        computedSettable = try BaselineFixturePicker.propertyDescriptor_computedSettable(in: machO)
    }
}
