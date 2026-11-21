import Semantic

extension MultilineTypeFormatting {
    /// How one line that runs past the width is laid out over several lines.
    ///
    /// A generic argument list inside no other generic argument list is the
    /// outermost list of a type; when its closing `>` lies past the width,
    /// that type is long. Inside a long type, every generic argument list
    /// with two or more elements breaks. Any list — a long type's or not —
    /// breaks when one of its elements spans several lines. Nothing else
    /// breaks.
    ///
    /// `nil` when the line does not parse or has nothing to break, and so
    /// stays as printed.
    struct LineLayout {
        /// How many spaces one level of a broken list indents by.
        static let indentationWidth = 4

        private let nodes: [BracketTreeNode]

        private let leadingIndentation: Int

        private let sourceComponents: [AtomicComponent]

        init?(line: SourceLine, sourceComponents: [AtomicComponent], maximumLineWidth: Int) {
            guard let parsedNodes = BracketTree.parse(line, sourceComponents: sourceComponents) else { return nil }
            let decision = Self.decidingBreaks(
                in: parsedNodes,
                maximumLineWidth: maximumLineWidth,
                isInsideGenericArguments: false,
                isInsideLongType: false
            )
            guard decision.containsBrokenList else { return nil }
            self.nodes = decision.nodes
            self.leadingIndentation = line.leadingIndentation
            self.sourceComponents = sourceComponents
        }

        func emit(into builder: inout FormattedComponentBuilder) {
            emit(nodes, depth: 0, into: &builder)
        }

        // MARK: - Deciding

        /// `nodes` with every list's `isBroken` decided, bottom-up.
        private static func decidingBreaks(
            in nodes: [BracketTreeNode],
            maximumLineWidth: Int,
            isInsideGenericArguments: Bool,
            isInsideLongType: Bool
        ) -> (nodes: [BracketTreeNode], containsBrokenList: Bool) {
            var decidedNodes: [BracketTreeNode] = []
            decidedNodes.reserveCapacity(nodes.count)
            var containsBrokenList = false
            for node in nodes {
                guard case .list(var list) = node else {
                    decidedNodes.append(node)
                    continue
                }
                let isLongTypeRoot = list.kind == .genericArguments
                    && !isInsideGenericArguments
                    && list.closingColumn > maximumLineWidth
                let isInLongType = isInsideLongType || isLongTypeRoot
                let elementsAreInsideGenericArguments = isInsideGenericArguments || list.kind == .genericArguments
                var hasMultilineElement = false
                var decidedElements: [[BracketTreeNode]] = []
                decidedElements.reserveCapacity(list.elements.count)
                for element in list.elements {
                    let decision = decidingBreaks(
                        in: element,
                        maximumLineWidth: maximumLineWidth,
                        isInsideGenericArguments: elementsAreInsideGenericArguments,
                        isInsideLongType: isInLongType
                    )
                    hasMultilineElement = hasMultilineElement || decision.containsBrokenList
                    decidedElements.append(decision.nodes)
                }
                list.elements = decidedElements
                let hasElements = list.elements.contains { !$0.isEmpty }
                let breaksForItsArguments = isInLongType && list.kind == .genericArguments && list.elements.count >= 2
                list.isBroken = hasElements && (hasMultilineElement || breaksForItsArguments)
                containsBrokenList = containsBrokenList || list.isBroken
                decidedNodes.append(.list(list))
            }
            return (decidedNodes, containsBrokenList)
        }

        // MARK: - Emitting

        private func emit(_ nodes: [BracketTreeNode], depth: Int, into builder: inout FormattedComponentBuilder) {
            for node in nodes {
                switch node {
                case .text(let fragment):
                    builder.append(fragment)
                case .list(let list):
                    emit(list, depth: depth, into: &builder)
                }
            }
        }

        /// A list as printed, or — broken — its opening bracket closing its
        /// line, each element on a line of its own one level deeper, and its
        /// closing bracket on a line of its own back at `depth`.
        private func emit(_ list: BracketList, depth: Int, into builder: inout FormattedComponentBuilder) {
            builder.append(list.opening)
            guard list.isBroken else {
                for (elementIndex, element) in list.elements.enumerated() {
                    emit(element, depth: depth, into: &builder)
                    if elementIndex < list.separators.count {
                        builder.append(list.separators[elementIndex])
                    }
                }
                builder.append(list.closing)
                return
            }
            let elementDepth = depth + 1
            for (elementIndex, element) in list.elements.enumerated() {
                let precedingPunctuation = elementIndex == 0 ? list.opening : list.separators[elementIndex - 1]
                builder.appendLineBreak(
                    indentation: leadingIndentation + Self.indentationWidth * elementDepth,
                    identifier: identifier(of: precedingPunctuation)
                )
                emit(Self.trimmingWhitespace(of: element), depth: elementDepth, into: &builder)
                if elementIndex < list.separators.count {
                    builder.append(list.separators[elementIndex])
                }
            }
            builder.appendLineBreak(
                indentation: leadingIndentation + Self.indentationWidth * depth,
                identifier: identifier(of: list.closing)
            )
            builder.append(list.closing)
        }

        private func identifier(of fragment: SourceFragment) -> String? {
            sourceComponents[fragment.componentIndex].identifier
        }

        /// `element` without the whitespace it starts and ends with — the
        /// space after a `, ` above all, which a broken list replaces with a
        /// line break.
        private static func trimmingWhitespace(of element: [BracketTreeNode]) -> [BracketTreeNode] {
            var nodes = element
            while case .text(let fragment) = nodes.first {
                let trimmedText = fragment.text.drop(while: \.isWhitespace)
                if trimmedText.isEmpty {
                    nodes.removeFirst()
                    continue
                }
                nodes[0] = .text(SourceFragment(componentIndex: fragment.componentIndex, text: trimmedText))
                break
            }
            while case .text(let fragment) = nodes.last {
                guard let lastVisibleIndex = fragment.text.lastIndex(where: { !$0.isWhitespace }) else {
                    nodes.removeLast()
                    continue
                }
                nodes[nodes.count - 1] = .text(SourceFragment(componentIndex: fragment.componentIndex, text: fragment.text[...lastVisibleIndex]))
                break
            }
            return nodes
        }
    }
}
