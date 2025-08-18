import Foundation
import MachOSwiftSection

extension TypeWrapper {
    package func dumper<MachO: MachOSwiftSectionRepresentableWithCache>(options: DemangleOptions, in machO: MachO) -> any TypedDumper {
        switch self {
        case .enum(let `enum`):
            return EnumDumper(`enum`, options: options, in: machO)
        case .struct(let `struct`):
            return StructDumper(`struct`, options: options, in: machO)
        case .class(let `class`):
            return ClassDumper(`class`, options: options, in: machO)
        }
    }
}
