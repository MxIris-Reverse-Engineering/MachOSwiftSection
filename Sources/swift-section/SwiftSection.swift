import ArgumentParser

enum SwiftSection: String, CaseIterable, ExpressibleByArgument {
    case types
    case protocols
    case protocolConformances
    case associatedTypes
}
