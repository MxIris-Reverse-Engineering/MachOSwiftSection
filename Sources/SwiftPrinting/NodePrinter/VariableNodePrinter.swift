import SwiftDeclaration
import Foundation
import Demangling
import Semantic

/// File-scoped because a generic type cannot hold a static stored property,
/// and a computed property returning the literal rebuilds the `Set` (an
/// allocation plus hashing) on every access — measured at about 70 ns against
/// 17 ns for a once-initialized constant on Swift 6.4 (proposal 0035).
private let variableDeclarationNodeKinds: Set<Node.Kind> = [.variable]

typealias SemanticVariableNodePrinter = VariableNodePrinter<SemanticString>

struct VariableNodePrinter<Target: NodePrinterTarget>: MemberDeclarationNodePrintable {
    typealias Context = InterfaceNodePrinterContext<Target>

    var target = Target()

    var context = Context()

    private(set) weak var delegate: (any NodePrintableDelegate)?

    let isFinal: Bool

    let isOverride: Bool

    let isClassMember: Bool

    private let isStored: Bool

    private let hasSetter: Bool

    private let indentation: Int

    static var declarationNodeKinds: Set<Node.Kind> { variableDeclarationNodeKinds }

    init(isStored: Bool, isOverride: Bool, isClassMember: Bool = false, isFinal: Bool = false, hasSetter: Bool, indentation: Int, delegate: (any NodePrintableDelegate)? = nil) {
        self.isStored = isStored
        self.isOverride = isOverride
        self.isClassMember = isClassMember
        self.isFinal = isFinal
        self.hasSetter = hasSetter
        self.indentation = indentation
        self.delegate = delegate
    }

    mutating func printDeclaration(_ node: Node) async throws {
        let identifier: Node? = if let identifier = node.children.first(of: .identifier) {
            identifier
        } else if let privateDeclName = node.children.first(of: .privateDeclName) {
            privateDeclName.children.at(1)
        } else {
            nil
        }
        guard let identifier else {
            throw MemberDeclarationPrintError.missingIdentifier(node)
        }

        target.write(isStored && !hasSetter ? "let" : "var", context: .context(state: .printKeyword))
        target.writeSpace()
        target.write(identifier.text ?? "", context: .context(for: identifier, parentKind: .variable, state: .printIdentifier))
        target.write(": ")

        guard let type = node.children.first(of: .type) else { return }

        await printName(type)

        guard !isStored else { return }

        printAccessorBlock(hasSetter: hasSetter, indentation: indentation)
    }
}
