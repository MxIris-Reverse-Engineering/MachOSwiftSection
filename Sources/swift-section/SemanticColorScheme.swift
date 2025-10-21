import ArgumentParser

enum SemanticColorScheme: String, CaseIterable, ExpressibleByArgument, Sendable {
    case none
    case light
    case dark
}
