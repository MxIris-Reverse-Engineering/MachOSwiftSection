import Foundation
import MachOKit
import MachOSwiftSectionMacro

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

@dynamicMemberLookup
public struct Class {
    public let descriptor: ClassDescriptor
    public let genericContext: TypeGenericContext?
    public let resilientSuperclass: ResilientSuperclass?
    public let foreignMetadataInitialization: ForeignMetadataInitialization?
    public let singletonMetadataInitialization: SingletonMetadataInitialization?
    public let vTableDescriptorHeader: VTableDescriptorHeader?
    public let methodDescriptors: [MethodDescriptor]
    public let overrideTableHeader: OverrideTableHeader?
    public let methodOverrideDescriptors: [MethodOverrideDescriptor]
    public let objcResilientClassStubInfo: ObjCResilientClassStubInfo?
    public let canonicalSpecializedMetadatasListCount: CanonicalSpecializedMetadatasListCount?
    public let canonicalSpecializedMetadatas: [CanonicalSpecializedMetadatasListEntry]
    public let canonicalSpecializedMetadataAccessors: [CanonicalSpecializedMetadataAccessorsListEntry]
    public let canonicalSpecializedMetadatasCachingOnceToken: CanonicalSpecializedMetadatasCachingOnceToken?
    public let invertibleProtocolSet: InvertibleProtocolSet?
    public let singletonMetadataPointer: SingletonMetadataPointer?
    public let methodDefaultOverrideTableHeader: MethodDefaultOverrideTableHeader?
    public let methodDefaultOverrideDescriptors: [MethodDefaultOverrideDescriptor]

    @MachOImageGenerator
    public init(descriptor: ClassDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
        let genericContext = try descriptor.typeGenericContext(in: machOFile)
        self.genericContext = genericContext
        var currentOffset = descriptor.offset + descriptor.layoutSize
        if let genericContext {
            currentOffset += genericContext.size
        }
        if descriptor.hasResilientSuperclass {
            self.resilientSuperclass = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: ResilientSuperclass.self)
        } else {
            self.resilientSuperclass = nil
        }

        if descriptor.hasForeignMetadataInitialization {
            self.foreignMetadataInitialization = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: ForeignMetadataInitialization.self)
        } else {
            self.foreignMetadataInitialization = nil
        }

        if descriptor.hasSingletonMetadataInitialization {
            self.singletonMetadataInitialization = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: SingletonMetadataInitialization.self)
        } else {
            self.singletonMetadataInitialization = nil
        }

        if descriptor.hasVTable {
            let vTableDescriptorHeader: VTableDescriptorHeader = try machOFile.readElement(offset: currentOffset)
            self.vTableDescriptorHeader = vTableDescriptorHeader
            currentOffset.offset(of: VTableDescriptorHeader.self)
            self.methodDescriptors = try machOFile.readElements(offset: currentOffset, numberOfElements: vTableDescriptorHeader.vTableSize.cast())
            currentOffset.offset(of: MethodDescriptor.self, numbersOfElements: vTableDescriptorHeader.vTableSize.cast())
        } else {
            self.vTableDescriptorHeader = nil
            self.methodDescriptors = []
        }

        if descriptor.hasOverrideTable {
            let overrideTableHeader: OverrideTableHeader = try machOFile.readElement(offset: currentOffset)
            self.overrideTableHeader = overrideTableHeader
            currentOffset.offset(of: OverrideTableHeader.self)
            self.methodOverrideDescriptors = try machOFile.readElements(offset: currentOffset, numberOfElements: overrideTableHeader.numEntries.cast())
            currentOffset.offset(of: MethodOverrideDescriptor.self, numbersOfElements: overrideTableHeader.numEntries.cast())
        } else {
            self.overrideTableHeader = nil
            self.methodOverrideDescriptors = []
        }

        if descriptor.hasObjCResilientClassStub {
            self.objcResilientClassStubInfo = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: ObjCResilientClassStubInfo.self)
        } else {
            self.objcResilientClassStubInfo = nil
        }

        if descriptor.hasCanonicalMetadataPrespecializations {
            let count: CanonicalSpecializedMetadatasListCount = try machOFile.readElement(offset: currentOffset)
            self.canonicalSpecializedMetadatasListCount = count
            currentOffset.offset(of: CanonicalSpecializedMetadatasListCount.self)
            let countValue = count.rawValue
            self.canonicalSpecializedMetadatas = try machOFile.readElements(offset: currentOffset, numberOfElements: countValue.cast())
            currentOffset.offset(of: CanonicalSpecializedMetadatasListEntry.self, numbersOfElements: countValue.cast())
            self.canonicalSpecializedMetadataAccessors = try machOFile.readElements(offset: currentOffset, numberOfElements: countValue.cast())
            currentOffset.offset(of: CanonicalSpecializedMetadataAccessorsListEntry.self, numbersOfElements: countValue.cast())
            self.canonicalSpecializedMetadatasCachingOnceToken = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: CanonicalSpecializedMetadatasCachingOnceToken.self)
        } else {
            self.canonicalSpecializedMetadatasListCount = nil
            self.canonicalSpecializedMetadatas = []
            self.canonicalSpecializedMetadataAccessors = []
            self.canonicalSpecializedMetadatasCachingOnceToken = nil
        }

        if descriptor.flags.contains(.hasInvertibleProtocols) {
            self.invertibleProtocolSet = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: InvertibleProtocolSet.self)
        } else {
            self.invertibleProtocolSet = nil
        }

        if descriptor.hasSingletonMetadataPointer {
            self.singletonMetadataPointer = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: SingletonMetadataPointer.self)
        } else {
            self.singletonMetadataPointer = nil
        }

        if descriptor.hasDefaultOverrideTable {
            let methodDefaultOverrideTableHeader: MethodDefaultOverrideTableHeader = try machOFile.readElement(offset: currentOffset)
            self.methodDefaultOverrideTableHeader = methodDefaultOverrideTableHeader
            currentOffset.offset(of: MethodDefaultOverrideTableHeader.self)
            self.methodDefaultOverrideDescriptors = try machOFile.readElements(offset: currentOffset, numberOfElements: methodDefaultOverrideTableHeader.numEntries.cast())
            currentOffset.offset(of: MethodDefaultOverrideDescriptor.self, numbersOfElements: methodDefaultOverrideTableHeader.numEntries.cast())
        } else {
            self.methodDefaultOverrideTableHeader = nil
            self.methodDefaultOverrideDescriptors = []
        }
    }

    public subscript<T>(dynamicMember member: KeyPath<ClassDescriptor, T>) -> T {
        return descriptor[keyPath: member]
    }
}

extension Class: Dumpable {
    @MachOImageGenerator
    @StringBuilder
    public func dump(using options: SymbolPrintOptions, in machOFile: MachOFile) throws -> String {
        try "class \(descriptor.fullname(in: machOFile))"

        if let genericContext {
            try genericContext.dumpGenericParameters(in: machOFile)
        }
        
        if let superclassMangledName = try descriptor.superclassTypeMangledName(in: machOFile) {
            try ": \(MetadataReader.demangleType(for: superclassMangledName, in: machOFile, using: options))"
        } else if let resilientSuperclass, let kind = descriptor.resilientSuperclassReferenceKind, let superclass = try resilientSuperclass.superclass(for: kind, in: machOFile) {
            ": \(superclass)"
        }
        
        if let genericContext, genericContext.requirements.count > 0 {
            " where "
            try genericContext.dumpGenericRequirements(using: options, in: machOFile)
        }
        
        " {"

        for (offset, fieldRecord) in try descriptor.fieldDescriptor(in: machOFile).records(in: machOFile).offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            let demangledTypeName = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machOFile), in: machOFile, using: options)

            let fieldName = try fieldRecord.fieldName(in: machOFile)

            if fieldRecord.flags.contains(.isVariadic) {
                if demangledTypeName.hasWeakPrefix {
                    "weak var "
                } else if fieldName.hasLazyPrefix {
                    "lazy var "
                } else {
                    "var "
                }
            } else {
                "let "
            }

            "\(fieldName.stripLazyPrefix): \(demangledTypeName.stripWeakPrefix)"

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, descriptor) in methodDescriptors.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            "[\(descriptor.flags.kind)] "

            if !descriptor.flags.isInstance, descriptor.flags.kind != .`init` {
                "static "
            }

            if descriptor.flags.isDynamic {
                "dynamic "
            }

            if descriptor.flags.kind == .method {
                "func "
            }

            if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                (try? MetadataReader.demangleSymbol(for: symbol, in: machOFile, using: options)) ?? "Demangle Error"
            } else if !descriptor.implementation.isNull {
                "\(descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)))"
            } else {
                "Symbol not found"
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, descriptor) in methodOverrideDescriptors.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            "override "

//            if !descriptor.method.res, descriptor.flags.kind != .`init` {
//                "class "
//            }
//
//            if descriptor.flags.isDynamic {
//                "dynamic "
//            }
//
//            if descriptor.flags.kind == .method {
//                "func "
//            }

            if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                (try? MetadataReader.demangleSymbol(for: symbol, in: machOFile, using: options)) ?? "Error"
            } else {
                "Symbol not found"
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, descriptor) in methodDefaultOverrideDescriptors.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            "default override "

            if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                (try? MetadataReader.demangleSymbol(for: symbol, in: machOFile, using: options)) ?? "Error"
            } else {
                "Symbol not found"
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        "}"
    }
}
