import SwiftDeclaration
import Foundation
import Demangling
import Semantic

typealias SemanticSubscriptNodePrinter = SubscriptNodePrinter<SemanticString>

struct SubscriptNodePrinter<Target: NodePrinterTarget>: MemberDeclarationNodePrintable {
    typealias Context = InterfaceNodePrinterContext<Target>

    var target = Target()

    var context = Context()

    private(set) weak var delegate: (any NodePrintableDelegate)?

    let isFinal: Bool

    let isOverride: Bool

    let isClassMember: Bool

    private let hasSetter: Bool

    private let indentation: Int

    static var declarationNodeKinds: Set<Node.Kind> { [.subscript] }

    init(isOverride: Bool, isClassMember: Bool = false, isFinal: Bool = false, hasSetter: Bool, indentation: Int, delegate: (any NodePrintableDelegate)? = nil) {
        self.isOverride = isOverride
        self.isClassMember = isClassMember
        self.isFinal = isFinal
        self.hasSetter = hasSetter
        self.indentation = indentation
        self.delegate = delegate
    }

    mutating func printDeclaration(_ node: Node) async throws {
        target.write("subscript", context: .context(state: .printKeyword))

        var subscriptNode = node
        if subscriptNode.children.at(1)?.isKind(of: .labelList) == false {
            subscriptNode = NodeBuilder(subscriptNode).insertingChild(Node.create(kind: .labelList), at: 1)
        }

        if let type = subscriptNode.children.first(of: .type), let functionType = type.children.first {
            await printLabelList(name: subscriptNode, type: functionType, genericFunctionTypeList: nil)
        }
        await printWhereClause(of: subscriptNode)

        printAccessorBlock(hasSetter: hasSetter, indentation: indentation)
    }
}
