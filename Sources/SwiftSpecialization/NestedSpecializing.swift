import MachOSwiftSection

/// Abstraction over the generic-specialization engine, declared in the base
/// declaration model so `TypeDefinition` can drive nested-child derivation
/// without depending on `SwiftIndexing` — where the concrete
/// `GenericSpecializer` lives, coupled to `SwiftDeclarationIndexer`. The
/// engine conforms to this protocol in `SwiftIndexing`, keeping `SwiftIndexing`
/// and `SwiftPrinting` peers that both sit above this base module.
public protocol NestedSpecializing {
    func makeRequest(
        for type: TypeContextDescriptorWrapper,
        candidateOptions: SpecializationRequest.CandidateOptions
    ) throws -> SpecializationRequest

    func specialize(
        _ request: SpecializationRequest,
        with selection: SpecializationSelection,
        metadataRequest: MetadataRequest
    ) throws -> SpecializationResult
}
