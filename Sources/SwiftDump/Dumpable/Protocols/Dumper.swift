import Semantic

protocol Dumper {
    @SemanticStringBuilder var body: SemanticString { get throws }
}
