import Foundation
import MachOKit

public struct ClassDescriptor: LocatableLayoutWrapper, TypeContextDescriptorProtocol {
    public struct Layout: ClassDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer<ContextDescriptorWrapper?>
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeOffset
        public let fieldDescriptor: RelativeDirectPointer<FieldDescriptor>
        public let superclassType: RelativeDirectPointer<MangledName>
        public let metadataNegativeSizeInWordsOrResilientMetadataBounds: UInt32
        public let metadataPositiveSizeInWordsOrExtraClassFlags: UInt32
        public let numImmediateMembers: UInt32
        public let numFields: UInt32
        public let fieldOffsetVectorOffset: UInt32
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}
