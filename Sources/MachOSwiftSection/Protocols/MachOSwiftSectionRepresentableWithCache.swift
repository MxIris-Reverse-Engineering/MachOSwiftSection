import MachOKit
import MachOExtensions
import MachOReading

public protocol MachOSwiftSectionRepresentableWithCache: MachORepresentableWithCache, Readable {
    associatedtype SwiftSection: SwiftSectionRepresentable

    var swift: SwiftSection { get }
}

extension MachOFile: MachOSwiftSectionRepresentableWithCache {}
extension MachOImage: MachOSwiftSectionRepresentableWithCache {}
