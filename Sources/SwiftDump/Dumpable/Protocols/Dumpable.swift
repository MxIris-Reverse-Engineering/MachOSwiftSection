import Demangle
import MachOKit
import Semantic
import MachOFoundation
import MachOSwiftSection

public typealias DemangleOptions = Demangle.DemangleOptions

public protocol Dumpable {
    func dump<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
}




