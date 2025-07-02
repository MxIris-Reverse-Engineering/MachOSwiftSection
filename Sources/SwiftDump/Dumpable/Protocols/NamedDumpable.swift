import MachOKit
import Semantic

public protocol NamedDumpable: Dumpable {
    func dumpName(using options: DemangleOptions, in machO: MachOFile) throws -> SemanticString
    func dumpName(using options: DemangleOptions, in machO: MachOImage) throws -> SemanticString
}
