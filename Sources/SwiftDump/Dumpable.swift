import Demangle
import MachOKit
import Semantic

public typealias DemangleOptions = Demangle.DemangleOptions

public protocol Dumpable {
    func dump(using options: DemangleOptions, in machO: MachOFile) throws -> SemanticString
    func dump(using options: DemangleOptions, in machO: MachOImage) throws -> SemanticString
}

public protocol NamedDumpable: Dumpable {
    func dumpName(using options: DemangleOptions, in machO: MachOFile) throws -> SemanticString
    func dumpName(using options: DemangleOptions, in machO: MachOImage) throws -> SemanticString
}

public protocol ConformedDumpable: Dumpable {
    func dumpTypeName(using options: DemangleOptions, in machO: MachOFile) throws -> SemanticString
    func dumpProtocolName(using options: DemangleOptions, in machO: MachOFile) throws -> SemanticString
    func dumpTypeName(using options: DemangleOptions, in machO: MachOImage) throws -> SemanticString
    func dumpProtocolName(using options: DemangleOptions, in machO: MachOImage) throws -> SemanticString
}
