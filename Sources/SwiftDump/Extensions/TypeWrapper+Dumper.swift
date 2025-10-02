import Foundation
import MachOSwiftSection

extension TypeContextWrapper {
    package func dumper<MachO: MachOSwiftSectionRepresentableWithCache>(using configuration: DumperConfiguration, in machO: MachO) -> any TypedDumper {
        switch self {
        case .enum(let `enum`):
            return EnumDumper(`enum`, using: configuration, in: machO)
        case .struct(let `struct`):
            return StructDumper(`struct`, using: configuration, in: machO)
        case .class(let `class`):
            return ClassDumper(`class`, using: configuration, in: machO)
        }
    }
}
