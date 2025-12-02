import Foundation
import MachOKit
import MachOFoundation

// template <typename Runtime>
// class swift_ptrauth_struct_context_descriptor(ClassDescriptor)
//    TargetClassDescriptor final
//    : public TargetTypeContextDescriptor<Runtime>,
//      public TrailingGenericContextObjects<TargetClassDescriptor<Runtime>,
//                              TargetTypeGenericContextDescriptorHeader,
//                              additional trailing objects:
//                              TargetResilientSuperclass<Runtime>,
//                              TargetForeignMetadataInitialization<Runtime>,
//                              TargetSingletonMetadataInitialization<Runtime>,
//                              TargetVTableDescriptorHeader<Runtime>,
//                              TargetMethodDescriptor<Runtime>,
//                              TargetOverrideTableHeader<Runtime>,
//                              TargetMethodOverrideDescriptor<Runtime>,
//                              TargetObjCResilientClassStubInfo<Runtime>,
//                              TargetCanonicalSpecializedMetadatasListCount<Runtime>,
//                              TargetCanonicalSpecializedMetadatasListEntry<Runtime>,
//                              TargetCanonicalSpecializedMetadataAccessorsListEntry<Runtime>,
//                              TargetCanonicalSpecializedMetadatasCachingOnceToken<Runtime>,
//                              InvertibleProtocolSet,
//                              TargetSingletonMetadataPointer<Runtime>,
//                              TargetMethodDefaultOverrideTableHeader<Runtime>,
//                              TargetMethodDefaultOverrideDescriptor<Runtime>>

public struct Class: TopLevelType, ContextProtocol {
    public let descriptor: ClassDescriptor
    public private(set) var genericContext: TypeGenericContext?
    public private(set) var resilientSuperclass: ResilientSuperclass?
    public private(set) var foreignMetadataInitialization: ForeignMetadataInitialization?
    public private(set) var singletonMetadataInitialization: SingletonMetadataInitialization?
    public private(set) var vTableDescriptorHeader: VTableDescriptorHeader?
    public private(set) var methodDescriptors: [MethodDescriptor] = []
    public private(set) var overrideTableHeader: OverrideTableHeader?
    public private(set) var methodOverrideDescriptors: [MethodOverrideDescriptor] = []
    public private(set) var objcResilientClassStubInfo: ObjCResilientClassStubInfo?
    public private(set) var canonicalSpecializedMetadatasListCount: CanonicalSpecializedMetadatasListCount?
    public private(set) var canonicalSpecializedMetadatas: [CanonicalSpecializedMetadatasListEntry] = []
    public private(set) var canonicalSpecializedMetadataAccessors: [CanonicalSpecializedMetadataAccessorsListEntry] = []
    public private(set) var canonicalSpecializedMetadatasCachingOnceToken: CanonicalSpecializedMetadatasCachingOnceToken?
    public private(set) var invertibleProtocolSet: InvertibleProtocolSet?
    public private(set) var singletonMetadataPointer: SingletonMetadataPointer?
    public private(set) var methodDefaultOverrideTableHeader: MethodDefaultOverrideTableHeader?
    public private(set) var methodDefaultOverrideDescriptors: [MethodDefaultOverrideDescriptor] = []

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(descriptor: ClassDescriptor, in machO: MachO) throws {
        self.descriptor = descriptor
        let genericContext = try descriptor.typeGenericContext(in: machO)
        self.genericContext = genericContext
        var currentOffset = descriptor.offset + descriptor.layoutSize
        if let genericContext {
            currentOffset += genericContext.size
        }
        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: machO)
    }
    
    public init(descriptor: ClassDescriptor) throws {
        self.descriptor = descriptor
        let genericContext = try descriptor.typeGenericContext()
        self.genericContext = genericContext
        var currentOffset = descriptor.layoutSize
        if let genericContext {
            currentOffset += genericContext.size
        }
        try initialize(descriptor: descriptor, currentOffset: &currentOffset, in: descriptor.asPointer)
    }
    
    private mutating func initialize<Reader: Readable>(descriptor: ClassDescriptor, currentOffset: inout Int, in reader: Reader) throws {
        if descriptor.hasResilientSuperclass {
            let resilientSuperclass: ResilientSuperclass = try reader.readWrapperElement(offset: currentOffset)
            self.resilientSuperclass = resilientSuperclass
            currentOffset.offset(of: ResilientSuperclass.self)
        } else {
            self.resilientSuperclass = nil
        }

        if descriptor.hasForeignMetadataInitialization {
            let foreignMetadataInitialization: ForeignMetadataInitialization = try reader.readWrapperElement(offset: currentOffset)
            self.foreignMetadataInitialization = foreignMetadataInitialization
            currentOffset.offset(of: ForeignMetadataInitialization.self)
        } else {
            self.foreignMetadataInitialization = nil
        }

        if descriptor.hasSingletonMetadataInitialization {
            let singletonMetadataInitialization: SingletonMetadataInitialization = try reader.readWrapperElement(offset: currentOffset)
            self.singletonMetadataInitialization = singletonMetadataInitialization
            currentOffset.offset(of: SingletonMetadataInitialization.self)
        } else {
            self.singletonMetadataInitialization = nil
        }

        if descriptor.hasVTable {
            let vTableDescriptorHeader: VTableDescriptorHeader = try reader.readWrapperElement(offset: currentOffset)
            self.vTableDescriptorHeader = vTableDescriptorHeader
            currentOffset.offset(of: VTableDescriptorHeader.self)
            let methodDescriptors: [MethodDescriptor] = try reader.readWrapperElements(offset: currentOffset, numberOfElements: vTableDescriptorHeader.vTableSize.cast())
            self.methodDescriptors = methodDescriptors
            currentOffset.offset(of: MethodDescriptor.self, numbersOfElements: vTableDescriptorHeader.vTableSize.cast())
        } else {
            self.vTableDescriptorHeader = nil
            self.methodDescriptors = []
        }

        if descriptor.hasOverrideTable {
            let overrideTableHeader: OverrideTableHeader = try reader.readWrapperElement(offset: currentOffset)
            self.overrideTableHeader = overrideTableHeader
            currentOffset.offset(of: OverrideTableHeader.self)
            let methodOverrideDescriptors: [MethodOverrideDescriptor] = try reader.readWrapperElements(offset: currentOffset, numberOfElements: overrideTableHeader.numEntries.cast())
            self.methodOverrideDescriptors = methodOverrideDescriptors
            currentOffset.offset(of: MethodOverrideDescriptor.self, numbersOfElements: overrideTableHeader.numEntries.cast())
        } else {
            self.overrideTableHeader = nil
            self.methodOverrideDescriptors = []
        }

        if descriptor.hasObjCResilientClassStub {
            let objcResilientClassStubInfo: ObjCResilientClassStubInfo = try reader.readWrapperElement(offset: currentOffset)
            self.objcResilientClassStubInfo = objcResilientClassStubInfo
            currentOffset.offset(of: ObjCResilientClassStubInfo.self)
        } else {
            self.objcResilientClassStubInfo = nil
        }

        if descriptor.hasCanonicalMetadataPrespecializations {
            let count: CanonicalSpecializedMetadatasListCount = try reader.readElement(offset: currentOffset)
            self.canonicalSpecializedMetadatasListCount = count
            currentOffset.offset(of: CanonicalSpecializedMetadatasListCount.self)
            let countValue = count.rawValue
            let canonicalSpecializedMetadatas: [CanonicalSpecializedMetadatasListEntry] = try reader.readWrapperElements(offset: currentOffset, numberOfElements: countValue.cast())
            self.canonicalSpecializedMetadatas = canonicalSpecializedMetadatas
            currentOffset.offset(of: CanonicalSpecializedMetadatasListEntry.self, numbersOfElements: countValue.cast())
            let canonicalSpecializedMetadataAccessors: [CanonicalSpecializedMetadataAccessorsListEntry] = try reader.readWrapperElements(offset: currentOffset, numberOfElements: countValue.cast())
            self.canonicalSpecializedMetadataAccessors = canonicalSpecializedMetadataAccessors
            currentOffset.offset(of: CanonicalSpecializedMetadataAccessorsListEntry.self, numbersOfElements: countValue.cast())
            let canonicalSpecializedMetadatasCachingOnceToken: CanonicalSpecializedMetadatasCachingOnceToken = try reader.readWrapperElement(offset: currentOffset)
            self.canonicalSpecializedMetadatasCachingOnceToken = canonicalSpecializedMetadatasCachingOnceToken
            currentOffset.offset(of: CanonicalSpecializedMetadatasCachingOnceToken.self)
        } else {
            self.canonicalSpecializedMetadatasListCount = nil
            self.canonicalSpecializedMetadatas = []
            self.canonicalSpecializedMetadataAccessors = []
            self.canonicalSpecializedMetadatasCachingOnceToken = nil
        }

        if descriptor.flags.contains(.hasInvertibleProtocols) {
            let invertibleProtocolSet: InvertibleProtocolSet = try reader.readElement(offset: currentOffset)
            self.invertibleProtocolSet = invertibleProtocolSet
            currentOffset.offset(of: InvertibleProtocolSet.self)
        } else {
            self.invertibleProtocolSet = nil
        }

        if descriptor.hasSingletonMetadataPointer {
            let singletonMetadataPointer: SingletonMetadataPointer = try reader.readWrapperElement(offset: currentOffset)
            self.singletonMetadataPointer = singletonMetadataPointer
            currentOffset.offset(of: SingletonMetadataPointer.self)
        } else {
            self.singletonMetadataPointer = nil
        }

        if descriptor.hasDefaultOverrideTable {
            let methodDefaultOverrideTableHeader: MethodDefaultOverrideTableHeader = try reader.readWrapperElement(offset: currentOffset)
            self.methodDefaultOverrideTableHeader = methodDefaultOverrideTableHeader
            currentOffset.offset(of: MethodDefaultOverrideTableHeader.self)
            let methodDefaultOverrideDescriptors: [MethodDefaultOverrideDescriptor] = try reader.readWrapperElements(offset: currentOffset, numberOfElements: methodDefaultOverrideTableHeader.numEntries.cast())
            self.methodDefaultOverrideDescriptors = methodDefaultOverrideDescriptors
            currentOffset.offset(of: MethodDefaultOverrideDescriptor.self, numbersOfElements: methodDefaultOverrideTableHeader.numEntries.cast())
        } else {
            self.methodDefaultOverrideTableHeader = nil
            self.methodDefaultOverrideDescriptors = []
        }
    }
}
