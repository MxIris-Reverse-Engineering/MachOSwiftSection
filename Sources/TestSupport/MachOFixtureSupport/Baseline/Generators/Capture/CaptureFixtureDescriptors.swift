import Foundation
import MachOFoundation
@testable import MachOSwiftSection

/// The three capture descriptors every capture baseline generator works
/// from, loaded once so the three baselines cannot drift apart.
package struct CaptureFixtureDescriptors {
    package let withoutMetadataSources: CaptureDescriptor
    package let withSingleMetadataSource: CaptureDescriptor
    package let withMultipleMetadataSources: CaptureDescriptor

    package var all: [CaptureDescriptor] {
        [withoutMetadataSources, withSingleMetadataSource, withMultipleMetadataSources]
    }

    package init(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        withoutMetadataSources = try BaselineFixturePicker.captureDescriptor_withoutMetadataSources(in: machO)
        withSingleMetadataSource = try BaselineFixturePicker.captureDescriptor_withSingleMetadataSource(in: machO)
        withMultipleMetadataSources = try BaselineFixturePicker.captureDescriptor_withMultipleMetadataSources(in: machO)
    }
}
