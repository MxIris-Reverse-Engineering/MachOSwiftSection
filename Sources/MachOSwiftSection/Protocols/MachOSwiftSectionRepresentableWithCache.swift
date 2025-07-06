import MachOKit
import MachOExtensions
import MachOReading

public protocol MachOSwiftSectionRepresentableWithCache: MachORepresentableWithCache, MachOReadable {
    associatedtype SwiftSection: SwiftSectionRepresentable

    var swift: SwiftSection { get }
}

extension MachOFile: MachOSwiftSectionRepresentableWithCache {}
extension MachOImage: MachOSwiftSectionRepresentableWithCache {}
