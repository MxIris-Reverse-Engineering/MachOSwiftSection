import Demangle
import MachOKit
import Semantic

public typealias DemangleOptions = Demangle.DemangleOptions

public protocol Dumpable {
    func dump(using options: DemangleOptions, in machO: MachOFile) throws -> SemanticString
    func dump(using options: DemangleOptions, in machO: MachOImage) throws -> SemanticString
}




