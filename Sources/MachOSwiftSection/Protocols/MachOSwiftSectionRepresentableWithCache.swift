import MachOKit
import MachOExtensions

public protocol MachOSwiftSectionRepresentableWithCache: MachORepresentableWithCache {
    associatedtype SwiftSection: SwiftSectionRepresentable

    var swift: SwiftSection { get }
}

extension MachOFile: MachOSwiftSectionRepresentableWithCache {}
extension MachOImage: MachOSwiftSectionRepresentableWithCache {}
