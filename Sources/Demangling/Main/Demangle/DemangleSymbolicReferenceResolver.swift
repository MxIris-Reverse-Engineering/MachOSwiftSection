public typealias DemangleSymbolicReferenceResolver = @Sendable (_ kind: SymbolicReferenceKind, _ directness: Directness, _ symbolicReferenceIndex: Int) -> Node?
