import Semantic
import MachOSwiftSection

package protocol Dumper {
    associatedtype Dumped
    associatedtype MachO: MachOSwiftSectionRepresentableWithCache
    
    @SemanticStringBuilder var declaration: SemanticString { get throws }
    @SemanticStringBuilder var body: SemanticString { get throws }
    
    init(_ dumped: Dumped, options: DemangleOptions, in machO: MachO)
}
