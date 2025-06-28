import MachOKit
import MachOExtensions

protocol MachOSwiftSectionRepresentableWithCache: MachORepresentableWithCache {
    associatedtype SwiftSection: SwiftSectionRepresentable

    var swift: SwiftSection { get }
}

extension MachOFile: MachOSwiftSectionRepresentableWithCache {}
extension MachOImage: MachOSwiftSectionRepresentableWithCache {}
