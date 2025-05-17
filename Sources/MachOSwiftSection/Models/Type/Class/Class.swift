import Foundation
import MachOKit

/*
 template <typename Runtime>
 class swift_ptrauth_struct_context_descriptor(ClassDescriptor)
     TargetClassDescriptor final
     : public TargetTypeContextDescriptor<Runtime>,
       public TrailingGenericContextObjects<TargetClassDescriptor<Runtime>,
                               TargetTypeGenericContextDescriptorHeader,
                               /*additional trailing objects:*/
                               TargetResilientSuperclass<Runtime>,
                               TargetForeignMetadataInitialization<Runtime>,
                               TargetSingletonMetadataInitialization<Runtime>,
                               TargetVTableDescriptorHeader<Runtime>,
                               TargetMethodDescriptor<Runtime>,
                               TargetOverrideTableHeader<Runtime>,
                               TargetMethodOverrideDescriptor<Runtime>,
                               TargetObjCResilientClassStubInfo<Runtime>,
                               TargetCanonicalSpecializedMetadatasListCount<Runtime>,
                               TargetCanonicalSpecializedMetadatasListEntry<Runtime>,
                               TargetCanonicalSpecializedMetadataAccessorsListEntry<Runtime>,
                               TargetCanonicalSpecializedMetadatasCachingOnceToken<Runtime>,
                               InvertibleProtocolSet,
                               TargetSingletonMetadataPointer<Runtime>,
                               TargetMethodDefaultOverrideTableHeader<Runtime>,
                               TargetMethodDefaultOverrideDescriptor<Runtime>>
 */
public struct Class {
    public let descriptor: ClassDescriptor
    
    public init(descriptor: ClassDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
    }
}
