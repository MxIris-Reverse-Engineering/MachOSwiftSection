package struct Indent: CustomStringConvertible, SemanticStringComponent {
    package let level: Int

    package var string: String { description }

    package var type: SemanticType { .standard }

    package init(level: Int) {
        self.level = level
    }

    package var description: String {
        if level > 0 {
            String(repeating: " ", count: level * 4)
        } else {
            String()
        }
    }
}

package struct BreakLine: CustomStringConvertible, SemanticStringComponent {
    package var string: String { description }

    package var type: SemanticType { .standard }

    package var description: String { "\n" }

    package init() {}
}

package struct Space: CustomStringConvertible, SemanticStringComponent {
    package var string: String { description }

    package var type: SemanticType { .standard }

    package var description: String { " " }

    package init() {}
}
