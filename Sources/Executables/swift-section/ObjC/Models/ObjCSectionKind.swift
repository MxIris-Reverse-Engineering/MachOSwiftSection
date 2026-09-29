import ArgumentParser

/// The kinds of declaration `dump` can emit. With none given it emits all of
/// them, in the order listed here.
enum ObjCSectionKind: String, CaseIterable, ExpressibleByArgument, Sendable {
    case classes
    case protocols
    case categories
    case structs
    case unions
}
