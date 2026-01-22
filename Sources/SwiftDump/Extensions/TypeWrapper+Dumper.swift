import Foundation
import MachOSwiftSection

extension TypeContextWrapper {
    package func dumper(using configuration: DumperConfiguration, genericParamSpecializations: [(Metadata, [ProtocolWitnessTable]?)] = [], in machO: some MachOSwiftSectionRepresentableWithCache) -> any TypedDumper {
        switch self {
        case .enum(let type):
            let metadata: EnumMetadata? = if type.descriptor.isGeneric {
                if !genericParamSpecializations.isEmpty {
                    try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init(), args: genericParamSpecializations).value.resolve(in: machO).enum
                } else {
                    nil
                }
            } else {
                try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).enum
            }

            return EnumDumper(type, metadata: metadata, using: configuration, in: machO)
        case .struct(let type):
            let metadata: StructMetadata? = if type.descriptor.isGeneric {
                if !genericParamSpecializations.isEmpty {
                    try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init(), args: genericParamSpecializations).value.resolve(in: machO).struct
                } else {
                    nil
                }
            } else {
                try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).struct
            }
            return StructDumper(type, metadata: metadata, using: configuration, in: machO)
        case .class(let type):
            let metadata: ClassMetadataObjCInterop? = if type.descriptor.isGeneric {
                if !genericParamSpecializations.isEmpty {
                    try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init(), args: genericParamSpecializations).value.resolve(in: machO).class
                } else {
                    nil
                }
            } else {
                try? type.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).class
            }
            return ClassDumper(type, metadata: metadata, using: configuration, in: machO)
        }
    }
}
