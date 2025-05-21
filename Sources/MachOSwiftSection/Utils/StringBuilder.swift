@resultBuilder
public enum StringBuilder {
    public static func buildBlock() -> String {
        ""
    }
    
    public static func buildBlock(_ components: String...) -> [String] {
        components
    }
    
    public static func buildBlock(_ components: CustomStringConvertible...) -> [String] {
        components.map { $0.description }
    }
    
    public static func buildBlock(_ components: [String]...) -> [String] {
        components.flatMap { $0 }
    }
    
    public static func buildBlock(_ components: [CustomStringConvertible]...) -> [String] {
        components.flatMap { $0.map { $0.description } }
    }

    public static func buildFinalResult(_ components: [String]) -> String {
        components.joined()
    }
}

extension StringBuilder {
    public static func buildPartialBlock(first: CustomStringConvertible) -> [String] {
        [first.description]
    }

    public static func buildPartialBlock(accumulated: [String], next: CustomStringConvertible) -> [String] {
        accumulated + [next.description]
    }

    public static func buildPartialBlock(first: String) -> [String] {
        [first]
    }

    public static func buildPartialBlock(accumulated: [String], next: String) -> [String] {
        accumulated + [next]
    }

    public static func buildPartialBlock(first: [String]) -> [String] {
        first
    }

    public static func buildPartialBlock(accumulated: [String], next: [String]) -> [String] {
        accumulated + next
    }
}

extension StringBuilder {
    public static func buildOptional(_ component: [String]?) -> [String] {
        component ?? []
    }
}

extension StringBuilder {
    public static func buildEither(first component: [String]) -> [String] {
        component
    }

    public static func buildEither(second component: [String]) -> [String] {
        component
    }
}

extension StringBuilder {
    public static func buildArray(_ components: [[String]]) -> [String] {
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
