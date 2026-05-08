import Foundation
import MachOSwiftSection

extension TypeContextWrapper {
    package func dumper(using configuration: DumperConfiguration, metadata: MetadataWrapper? = nil, in machO: some MachOSwiftSectionRepresentableWithCache) -> any TypedDumper {
        switch self {
        case .enum(let type):
            let resolvedMetadata: EnumMetadata?
            if let metadata {
                // Both `enum` and `optional` wrappers carry an `EnumMetadata`
                // payload — the runtime distinguishes them by kind only, but
                // the descriptor-level dumper needs the underlying struct
                // either way.
                resolvedMetadata = metadata.enum ?? metadata.optional
            } else if type.descriptor.isGeneric {
                resolvedMetadata = nil
            } else {
                resolvedMetadata = try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).enum
            }

            return EnumDumper(type, metadata: resolvedMetadata, using: configuration, in: machO)
        case .struct(let type):
            let resolvedMetadata: StructMetadata?
            if let metadata {
                resolvedMetadata = metadata.struct
            } else if type.descriptor.isGeneric {
                resolvedMetadata = nil
            } else {
                resolvedMetadata = try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).struct
            }
            return StructDumper(type, metadata: resolvedMetadata, using: configuration, in: machO)
        case .class(let type):
            let resolvedMetadata: ClassMetadataObjCInterop?
            if let metadata {
                resolvedMetadata = metadata.class
            } else if type.descriptor.isGeneric {
                resolvedMetadata = nil
            } else {
                resolvedMetadata = try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).class
            }
            return ClassDumper(type, metadata: resolvedMetadata, using: configuration, in: machO)
        }
    }
}
