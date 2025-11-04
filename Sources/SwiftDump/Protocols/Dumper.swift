import Semantic
import MachOSwiftSection

package protocol Dumper {
    associatedtype Dumped
    associatedtype MachO: MachOSwiftSectionRepresentableWithCache
    
    @SemanticStringBuilder var declaration: SemanticString { get async throws }
    @SemanticStringBuilder var body: SemanticString { get async throws }
    
    init(_ dumped: Dumped, using configuration: DumperConfiguration, in machO: MachO)
}
