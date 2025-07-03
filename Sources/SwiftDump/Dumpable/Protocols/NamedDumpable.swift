import MachOKit
import Semantic
import MachOFoundation

public protocol NamedDumpable: Dumpable {
    func dumpName<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString
}
