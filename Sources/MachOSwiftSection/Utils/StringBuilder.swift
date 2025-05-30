@resultBuilder
internal enum StringBuilder {
    internal static func buildBlock() -> String {
        ""
    }

    internal static func buildBlock(_ components: String...) -> [String] {
        components
    }

    internal static func buildBlock(_ components: CustomStringConvertible...) -> [String] {
        components.map { $0.description }
    }

    internal static func buildBlock(_ components: [String]...) -> [String] {
        components.flatMap { $0 }
    }

    internal static func buildBlock(_ components: [CustomStringConvertible]...) -> [String] {
        components.flatMap { $0.map { $0.description } }
    }

    internal static func buildFinalResult(_ components: [String]) -> String {
        components.joined()
    }
}

extension StringBuilder {
    internal static func buildPartialBlock(first: CustomStringConvertible) -> [String] {
        [first.description]
    }

    internal static func buildPartialBlock(accumulated: [String], next: CustomStringConvertible) -> [String] {
        accumulated + [next.description]
    }

    internal static func buildPartialBlock(first: String) -> [String] {
        [first]
    }

    internal static func buildPartialBlock(accumulated: [String], next: String) -> [String] {
        accumulated + [next]
    }

    internal static func buildPartialBlock(first: [String]) -> [String] {
        first
    }

    internal static func buildPartialBlock(accumulated: [String], next: [String]) -> [String] {
        accumulated + next
    }
}

extension StringBuilder {
    internal static func buildOptional(_ component: [String]?) -> [String] {
        component ?? []
    }
}

extension StringBuilder {
    internal static func buildEither(first component: [String]) -> [String] {
        component
    }

    internal static func buildEither(second component: [String]) -> [String] {
        component
    }
}

extension StringBuilder {
    internal static func buildArray(_ components: [[String]]) -> [String] {
        components.flatMap {
            $0
        }
    }
}

struct Indent: CustomStringConvertible {
    let level: Int

    var description: String {
        String(repeating: " ", count: level * 4)
    }
}

struct BreakLine: CustomStringConvertible {
    var description: String {
        "\n"
    }
}

struct Space: CustomStringConvertible {
    var description: String {
        " "
    }
}
