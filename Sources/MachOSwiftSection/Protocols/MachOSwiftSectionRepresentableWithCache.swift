import MachOKit
import MachOExtensions

package protocol MachOSwiftSectionRepresentableWithCache: MachORepresentableWithCache {
    associatedtype SwiftSection: SwiftSectionRepresentable

    var swift: SwiftSection { get }
}

extension MachOFile: MachOSwiftSectionRepresentableWithCache {}
extension MachOImage: MachOSwiftSectionRepresentableWithCache {}
