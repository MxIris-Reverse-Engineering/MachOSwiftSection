@resultBuilder
package enum StringBuilder {
    package static func buildBlock() -> String {
        ""
    }

    package static func buildBlock(_ components: String...) -> [String] {
        components
    }

    package static func buildBlock(_ components: CustomStringConvertible...) -> [String] {
        components.map { $0.description }
    }

    package static func buildBlock(_ components: [String]...) -> [String] {
        components.flatMap { $0 }
    }

    package static func buildBlock(_ components: [CustomStringConvertible]...) -> [String] {
        components.flatMap { $0.map { $0.description } }
    }

    package static func buildFinalResult(_ components: [String]) -> String {
        components.joined()
    }
}

extension StringBuilder {
    package static func buildPartialBlock(first: CustomStringConvertible) -> [String] {
        [first.description]
    }

    package static func buildPartialBlock(accumulated: [String], next: CustomStringConvertible) -> [String] {
        accumulated + [next.description]
    }

    package static func buildPartialBlock(first: String) -> [String] {
        [first]
    }

    package static func buildPartialBlock(accumulated: [String], next: String) -> [String] {
        accumulated + [next]
    }

    package static func buildPartialBlock(first: [String]) -> [String] {
        first
    }

    package static func buildPartialBlock(accumulated: [String], next: [String]) -> [String] {
        accumulated + next
    }
}

extension StringBuilder {
    package static func buildOptional(_ component: [String]?) -> [String] {
        component ?? []
    }
}

extension StringBuilder {
    package static func buildEither(first component: [String]) -> [String] {
        component
    }

    package static func buildEither(second component: [String]) -> [String] {
        component
    }
}

extension StringBuilder {
    package static func buildArray(_ components: [[String]]) -> [String] {
        components.flatMap {
            $0
        }
    }
}
