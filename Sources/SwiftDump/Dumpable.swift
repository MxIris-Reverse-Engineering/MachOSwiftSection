import Demangle
import MachOKit
import Semantic

public typealias DemangleOptions = Demangle.DemangleOptions

public protocol Dumpable {
    func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString
    func dump(using options: DemangleOptions, in machOImage: MachOImage) throws -> SemanticString
}

public protocol NamedDumpable: Dumpable {
    func dumpName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString
    func dumpName(using options: DemangleOptions, in machOImage: MachOImage) throws -> SemanticString
}
