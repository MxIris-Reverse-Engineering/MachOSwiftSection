import Foundation
import MachOSwiftSection
import SwiftDeclarationRendering

extension TypeContextWrapper {
    package func dumper(using configuration: DumperConfiguration, metadata: MetadataWrapper? = nil, in machO: some FieldLayoutRenderable) -> any TypedDumper {
        switch self {
        case .enum(let type):
            let metadataContext: DumperMetadataContext<EnumMetadata>?
            // Both `enum` and `optional` wrappers carry an `EnumMetadata`
            // payload — the runtime distinguishes them by kind only, but
            // the descriptor-level dumper needs the underlying struct
            // either way.
            if let resolvedMetadata = metadata?.enum ?? metadata?.optional {
                metadataContext = .init(metadata: resolvedMetadata, readingContext: type.descriptor.isGeneric ? InProcessContext.shared : MachOContext(machO))
            } else if type.descriptor.isGeneric {
                metadataContext = nil
            } else {
                metadataContext = try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).enum.map { .init(metadata: $0, readingContext: MachOContext(machO)) }
            }
            return EnumDumper(type, metadataContext: metadataContext, using: configuration, in: machO)
        case .struct(let type):
            let metadataContext: DumperMetadataContext<StructMetadata>?
            if let metadata = metadata?.struct {
                metadataContext = .init(metadata: metadata, readingContext: type.descriptor.isGeneric ? InProcessContext.shared : MachOContext(machO))
            } else if type.descriptor.isGeneric {
                metadataContext = nil
            } else {
                metadataContext = try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).struct.map { .init(metadata: $0, readingContext: MachOContext(machO)) }
            }
            return StructDumper(type, metadataContext: metadataContext, using: configuration, in: machO)
        case .class(let type):
            let metadataContext: DumperMetadataContext<ClassMetadataObjCInterop>?
            if let metadata = metadata?.class {
                metadataContext = .init(metadata: metadata, readingContext: type.descriptor.isGeneric ? InProcessContext.shared : MachOContext(machO))
            } else if type.descriptor.isGeneric {
                metadataContext = nil
            } else {
                metadataContext = try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).class.map { .init(metadata: $0, readingContext: MachOContext(machO)) }
            }
            return ClassDumper(type, metadataContext: metadataContext, using: configuration, in: machO)
        }
    }
}
