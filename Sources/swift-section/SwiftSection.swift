import ArgumentParser

enum SwiftSection: String, ExpressibleByArgument, CaseIterable {
    case types
    case protocols
    case protocolConformances
    case associatedTypes
}
