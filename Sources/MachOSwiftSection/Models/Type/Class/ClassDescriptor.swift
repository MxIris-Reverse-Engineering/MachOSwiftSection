import Foundation
import MachOKit

public struct ClassDescriptor: LayoutWrapperWithOffset {
    public struct Layout: ClassDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeOffset
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeOffset
        public let fieldDescriptor: RelativeDirectPointer<FieldDescriptor>
        public let superclassType: RelativeOffset
        public let metadataNegativeSizeInWordsOrResilientMetadataBounds: UInt32
        public let metadataPositiveSizeInWordsOrExtraClassFlags: UInt32
        public let numImmediateMembers: UInt32
        public let numFields: UInt32
        public let fieldOffsetVector: UInt32
    }

    public let offset: Int

    public var layout: Layout

    public init(offset: Int, layout: Layout) {
        self.offset = offset
        self.layout = layout
    }
}
