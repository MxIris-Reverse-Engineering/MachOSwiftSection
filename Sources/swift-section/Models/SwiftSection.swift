import ArgumentParser

enum SwiftSection: String, CaseIterable, ExpressibleByArgument, Sendable {
    case types
    case protocols
    case protocolConformances
    case associatedTypes
}
