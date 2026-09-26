/// How a function parameter is passed, as recorded in
/// ``FunctionParameterTypeFlags``.
///
/// Mirrors `swift::ParameterOwnership` (`swift/ABI/MetadataValues.h`).
///
/// Named with a `Function` prefix rather than after the ABI type because
/// `Demangling` vends its own `ParameterOwnership`, and consumers such as
/// `SwiftInspection` import both modules unqualified.
public enum FunctionParameterOwnership: UInt8, Sendable {
    /// The context-dependent default — sometimes borrowing, sometimes
    /// consuming.
    case `default` = 0
    /// `inout`: an exclusive, mutating borrow.
    case inOut = 1
    /// `borrowing`: a non-exclusive, usually non-mutating borrow.
    case shared = 2
    /// `consuming`: an ownership transfer.
    case owned = 3
}
