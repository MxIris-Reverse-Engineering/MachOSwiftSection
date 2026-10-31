import Semantic

/// One comment the printers emit, as the segments its text is made of
/// (evolution proposal `comment-structure`).
///
/// Every comment's text is spelled out once, by one of the factories in
/// `StructuredComment+Factories.swift`, as a run of segments that each play
/// a role in it — the comment marker, a label, a value. The comment prints as
/// the single `.comment` atom the printers have always emitted: the
/// segments' texts concatenated. What the segments add is the role of each
/// part, which a print marking comment structure records around the same
/// text.
package struct StructuredComment: PlainAtomicSemanticComponent, Hashable, Sendable {
    package let segments: [Segment]

    /// The comment's text: every segment's, in order.
    package let string: String

    package var type: SemanticType { .comment }

    package init(segments: [Segment]) {
        self.segments = segments
        self.string = segments.text
    }
}

// MARK: - Segments

extension StructuredComment {
    /// A run of a comment's text and the role it plays there. The role is
    /// `nil` for text that plays none: the line breaks and the indentation
    /// inside a comment spanning several lines.
    package struct Segment: Hashable, Sendable {
        package let role: Role?

        package let text: String

        package init(_ role: Role?, _ text: String) {
            self.role = role
            self.text = text
        }

        /// The comment's own syntax — `// `, `/* `, ` */` — and the spaces
        /// that align a continuation line under the first one.
        package static func marker(_ text: String) -> Self { Self(.marker, text) }

        /// What the comment states: `Address`, `VTable offset`, `Type Layout`.
        package static func label(_ text: String) -> Self { Self(.label, text) }

        /// What narrows the label down: the accessor in `Address (getter)`.
        package static func qualifier(_ text: String) -> Self { Self(.qualifier, text) }

        /// Punctuation between the other segments: `: `, `, `, ` (`.
        package static func separator(_ text: String) -> Self { Self(.separator, text) }

        /// The name of one of several facts: `size` in a type layout.
        package static func key(_ text: String) -> Self { Self(.key, text) }

        /// A fact's value: an address, an offset, a count.
        package static func value(_ text: String) -> Self { Self(.value, text) }

        /// A declaration's name: a field, an enum case, a module.
        package static func name(_ text: String) -> Self { Self(.name, text) }

        /// A type's name.
        package static func type(_ text: String) -> Self { Self(.type, text) }

        /// The branches drawn in front of a row of the expanded field-offset
        /// tree: `│   ├── `.
        package static func treePrefix(_ text: String) -> Self { Self(.treePrefix, text) }

        /// Prose.
        package static func text(_ text: String) -> Self { Self(.text, text) }

        /// Text that plays no role.
        package static func plain(_ text: String) -> Self { Self(nil, text) }
    }

    /// What a segment of a comment is.
    ///
    /// Stands in for swift-semantic-string's `AnnotationSegment.Role` until
    /// its annotation regions ship (evolution proposal `comment-structure`).
    /// The members are named as there, so a segment written `.label` keeps
    /// its spelling once this becomes that type.
    package struct Role: Hashable, Sendable {
        package let rawValue: String

        private init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        package static let marker = Self("marker")
        package static let label = Self("label")
        package static let qualifier = Self("qualifier")
        package static let separator = Self("separator")
        package static let key = Self("key")
        package static let value = Self("value")
        package static let name = Self("name")
        package static let type = Self("type")
        package static let treePrefix = Self("treePrefix")
        package static let text = Self("text")
    }
}

extension [StructuredComment.Segment] {
    /// The segments' texts, concatenated.
    package var text: String {
        var text = ""
        for segment in self {
            text += segment.text
        }
        return text
    }
}

// MARK: - Comment Forms

extension StructuredComment {
    /// `// ` and `body`: a line comment.
    package static func line(_ body: [Segment]) -> Self {
        Self(segments: [.marker("// ")] + body)
    }

    /// `/* `, `body` and ` */`: an inline comment.
    package static func inline(_ body: [Segment]) -> Self {
        Self(segments: [.marker("/* ")] + body + [.marker(" */")])
    }

    /// A line comment that is all prose. Spaces it starts with align it
    /// under the line above, so they count as part of the marker.
    package static func note(_ text: String) -> Self {
        let indentation = text.prefix { $0 == " " }
        guard !indentation.isEmpty else {
            return line([.text(text)])
        }
        return line([.marker(String(indentation)), .text(String(text.dropFirst(indentation.count)))])
    }

    /// An inline comment that is all prose.
    package static func inlineNote(_ text: String) -> Self {
        inline([.text(text)])
    }
}
