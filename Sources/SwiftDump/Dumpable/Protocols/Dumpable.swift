import Demangle
import MachOKit
import Semantic
import MachOSwiftSection

public typealias DemangleOptions = Demangle.DemangleOptions

public protocol Dumpable {
    func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
}




