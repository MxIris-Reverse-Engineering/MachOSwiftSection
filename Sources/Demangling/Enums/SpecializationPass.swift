enum SpecializationPass: CaseIterable, Sendable {
    case allocBoxToStack
    case closureSpecializer
    case capturePromotion
    case capturePropagation
    case functionSignatureOpts
    case genericSpecializer
}
