import Semantic

package protocol NamedDumper: Dumper {
    @SemanticStringBuilder var name: SemanticString { get throws }
}
