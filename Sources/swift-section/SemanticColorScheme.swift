import ArgumentParser

enum SemanticColorScheme: String, CaseIterable, ExpressibleByArgument {
    case none
    case light
    case dark
}
