/// How a function type is differentiable, for the differentiable-programming
/// feature.
///
/// Present as one pointer-sized trailing word only when
/// ``FunctionTypeFlags/isDifferentiable`` is set.
///
/// Mirrors `swift::TargetFunctionMetadataDifferentiabilityKind`
/// (`swift/ABI/MetadataValues.h`).
///
/// Named with a `FunctionType` prefix rather than after the ABI type because
/// `Demangling` vends its own `FunctionMetadataDifferentiabilityKind`, and
/// consumers such as `SwiftInspection` import both modules unqualified.
public enum FunctionTypeDifferentiabilityKind: UInt64, Sendable {
    case nonDifferentiable = 0
    case forward = 1
    case reverse = 2
    case normal = 3
    case linear = 4
}
