import Semantic

protocol NamedDumper: Dumper {
    @SemanticStringBuilder var name: SemanticString { get throws }
}
