import MachOKit
import Semantic

public protocol ConformedDumpable: Dumpable {
    func dumpTypeName(using options: DemangleOptions, in machO: MachOFile) throws -> SemanticString
    func dumpProtocolName(using options: DemangleOptions, in machO: MachOFile) throws -> SemanticString
    func dumpTypeName(using options: DemangleOptions, in machO: MachOImage) throws -> SemanticString
    func dumpProtocolName(using options: DemangleOptions, in machO: MachOImage) throws -> SemanticString
}
