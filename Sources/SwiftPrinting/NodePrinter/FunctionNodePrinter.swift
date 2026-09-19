import SwiftDeclaration
import Foundation
import Demangling
import Semantic

struct FunctionNodePrinter: MemberDeclarationNodePrintable {
    typealias Context = InterfaceNodePrinterContext<SemanticString>

    var target: SemanticString = ""

    var context = Context()

    private(set) weak var delegate: (any NodePrintableDelegate)?

    let isFinal: Bool

    let isOverride: Bool

    let isClassMember: Bool

    static let declarationNodeKinds: Set<Node.Kind> = [.function, .boundGenericFunction, .allocator, .constructor]

    init(isOverride: Bool, isClassMember: Bool = false, isFinal: Bool = false, delegate: (any NodePrintableDelegate)? = nil) {
        self.isOverride = isOverride
        self.isClassMember = isClassMember
        self.isFinal = isFinal
        self.delegate = delegate
    }

    mutating func printDeclaration(_ node: Node) async throws {
        let (function, genericArguments) = splitBoundGenericFunction(node)

        if function.kind == .allocator {
            target.write("init", context: .context(state: .printKeyword))
            switch function.initFailabilityKind {
            case .optional:
                target.write("?")
            case .implicitlyUnwrappedOptional:
                target.write("!")
            case .none:
                break
            }
        } else {
            target.write("func", context: .context(state: .printKeyword))
            target.writeSpace()
            if let identifier = function.children.first(of: .identifier) {
                await printIdentifier(identifier, parentKind: .function)
            } else if let privateDeclName = function.children.first(of: .privateDeclName) {
                await printPrivateDeclName(privateDeclName, parentKind: .function)
            } else if let operatorNode = function.children.first(of: .prefixOperator, .infixOperator, .postfixOperator), let text = operatorNode.text {
                target.write(text + " ")
            }
        }

        if let type = function.children.first(of: .type), let functionType = type.children.first {
            await printLabelList(name: function, type: functionType, genericFunctionTypeList: genericArguments)
        }
        await printWhereClause(of: function)
    }
}

extension Node {
    enum InitFailabilityKind {
        case none
        case optional
        case implicitlyUnwrappedOptional
    }

    var initFailabilityKind: InitFailabilityKind {
        guard let returnType = first(of: .returnType),
              let type = returnType.children.first,
              let boundGenericEnum = type.children.first,
              boundGenericEnum.isKind(of: .boundGenericEnum),
              let enumNode = boundGenericEnum.children.first?.children.first,
              enumNode.kind == .enum,
              let moduleChild = enumNode.children.first,
              moduleChild.kind == .module,
              moduleChild.text == "Swift",
              let identifierChild = enumNode.children.at(1),
              identifierChild.kind == .identifier,
              let identifierText = identifierChild.text else {
            return .none
        }
        switch identifierText {
        case "Optional":
            return .optional
        case "ImplicitlyUnwrappedOptional":
            return .implicitlyUnwrappedOptional
        default:
            return .none
        }
    }

    var isReturnOptional: Bool {
        initFailabilityKind == .optional
    }
}
