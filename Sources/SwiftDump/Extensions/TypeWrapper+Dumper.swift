import Foundation
import MachOSwiftSection

extension TypeContextWrapper {
    package func dumper(using configuration: DumperConfiguration, in machO: some MachOSwiftSectionRepresentableWithCache) -> any TypedDumper {
        switch self {
        case .enum(let `enum`):
            
            let metadata: EnumMetadata? = if `enum`.descriptor.isGeneric {
                nil
            } else {
                try? `enum`.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).enum
            }
            
            return EnumDumper(`enum`, metadata: metadata, using: configuration, in: machO)
        case .struct(let `struct`):
            let metadata: StructMetadata? = if `struct`.descriptor.isGeneric {
                nil
            } else {
                try? `struct`.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).struct
            }
            return StructDumper(`struct`, metadata: metadata, using: configuration, in: machO)
        case .class(let `class`):
            let metadata: ClassMetadataObjCInterop? = if `class`.descriptor.isGeneric {
                nil
            } else {
                try? `class`.descriptor.metadataAccessorFunction(in: machO)?(request: .init()).value.resolve(in: machO).class
            }
            return ClassDumper(`class`, metadata: metadata, using: configuration, in: machO)
        }
    }
}
