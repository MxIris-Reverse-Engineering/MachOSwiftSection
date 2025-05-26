import Foundation
import MachOKit
import MachOSwiftSectionMacro

@dynamicMemberLookup
public struct Struct {
    public let descriptor: StructDescriptor
    public let genericContext: TypeGenericContext?
    public let foreignMetadataInitialization: ForeignMetadataInitialization?
    public let singletonMetadataInitialization: SingletonMetadataInitialization?
    public let canonicalSpecializedMetadatas: [CanonicalSpecializedMetadatasListEntry]
    public let canonicalSpecializedMetadatasListCount: CanonicalSpecializedMetadatasListCount?
    public let canonicalSpecializedMetadatasCachingOnceToken: CanonicalSpecializedMetadatasCachingOnceToken?
    public let invertibleProtocolSet: InvertibleProtocolSet?
    public let singletonMetadataPointer: SingletonMetadataPointer?

    private var _cacheDescription: String = ""

    @MachOImageGenerator
    public init(descriptor: StructDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor

        var currentOffset = descriptor.offset + descriptor.layoutSize

        let genericContext = try descriptor.typeGenericContext(in: machOFile)

        if let genericContext {
            currentOffset += genericContext.size
        }

        self.genericContext = genericContext

        let typeFlags = try required(descriptor.flags.kindSpecificFlags?.typeFlags)

        if typeFlags.hasForeignMetadataInitialization {
            self.foreignMetadataInitialization = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: ForeignMetadataInitialization.self)
        } else {
            self.foreignMetadataInitialization = nil
        }

        if typeFlags.hasSingletonMetadataInitialization {
            self.singletonMetadataInitialization = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: SingletonMetadataInitialization.self)
        } else {
            self.singletonMetadataInitialization = nil
        }

        if descriptor.hasCanonicalMetadataPrespecializations {
            let count: CanonicalSpecializedMetadatasListCount = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: CanonicalSpecializedMetadatasListCount.self)
            let countValue = count.rawValue
            let canonicalMetadataPrespecializations: [CanonicalSpecializedMetadatasListEntry] = try machOFile.readElements(offset: currentOffset, numberOfElements: countValue.cast())
            currentOffset.offset(of: CanonicalSpecializedMetadatasListEntry.self, numbersOfElements: countValue.cast())
            self.canonicalSpecializedMetadatas = canonicalMetadataPrespecializations
            self.canonicalSpecializedMetadatasListCount = count
            self.canonicalSpecializedMetadatasCachingOnceToken = try machOFile.readElement(offset: currentOffset)
            currentOffset.offset(of: CanonicalSpecializedMetadatasCachingOnceToken.self)
        } else {
            self.canonicalSpecializedMetadatas = []
            self.canonicalSpecializedMetadatasListCount = nil
            self.canonicalSpecializedMetadatasCachingOnceToken = nil
        }

        if descriptor.flags.hasInvertibleProtocols {
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
        
        do {
            _cacheDescription = try buildDescription(in: machOFile)
        } catch {
            _cacheDescription = "Error: \(error)"
        }
    }

    public subscript<T>(dynamicMember member: KeyPath<StructDescriptor, T>) -> T {
        return descriptor[keyPath: member]
    }

    @MachOImageGenerator
    @StringBuilder
    private func buildDescription(in machOFile: MachOFile) throws -> String {
        try "struct \(descriptor.fullname(in: machOFile)) {"

        for (offset, fieldRecord) in try descriptor.fieldDescriptor(in: machOFile).records(in: machOFile).offsetEnumerated() {
            
            BreakLine()
            
            Indent(level: 1)

            let demangledTypeName = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machOFile), in: machOFile)
            
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

        "}"
    }
}

extension Struct: CustomStringConvertible {
    public var description: String {
        return _cacheDescription
    }
}
