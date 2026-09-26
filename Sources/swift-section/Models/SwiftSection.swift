import ArgumentParser

enum SwiftSection: String, CaseIterable, ExpressibleByArgument, Sendable {
    case types
    case protocols
    case protocolConformances
    case associatedTypes
    /// Classes implemented through `@objc @implementation` — no `__swift5_*`
    /// presence; recognized from `__objc_classlist` joined with the symbol
    /// table (evolution proposal `objc-implementation-class-recognition`).
    case objcImplementationClasses
}
