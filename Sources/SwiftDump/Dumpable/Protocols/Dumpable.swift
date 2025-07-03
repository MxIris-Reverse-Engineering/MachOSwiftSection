import Demangle
import MachOKit
import Semantic
import MachOFoundation

public typealias DemangleOptions = Demangle.DemangleOptions

public protocol Dumpable {
    func dump<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
}




