import MachOKit
import Semantic
import MachOFoundation
import MachOSwiftSection

public protocol NamedDumpable: Dumpable {
    func dumpName<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
}
