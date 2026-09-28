import SwiftDeclaration
import Foundation
import Demangling
import Semantic

/// File-scoped because a generic type cannot hold a static stored property,
/// and a computed property returning the literal rebuilds the `Set` (an
/// allocation plus hashing) on every access — measured at about 70 ns against
/// 17 ns for a once-initialized constant on Swift 6.4 (proposal 0035).
private let functionDeclarationNodeKinds: Set<Node.Kind> = [.function, .boundGenericFunction, .allocator, .constructor]

typealias SemanticFunctionNodePrinter = FunctionNodePrinter<SemanticString>

struct FunctionNodePrinter<Target: NodePrinterTarget>: MemberDeclarationNodePrintable {
    typealias Context = InterfaceNodePrinterContext<Target>

    var target = Target()

    var context = Context()

    private(set) weak var delegate: (any NodePrintableDelegate)?

    let isFinal: Bool

    let isOverride: Bool

    let isClassMember: Bool

    static var declarationNodeKinds: Set<Node.Kind> { functionDeclarationNodeKinds }

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

    /// Whether the initializer this node declares is failable: whether ITS
    /// OWN result, the `returnType` child of its function type, is an
    /// Optional of its Self.
    ///
    /// Not a whole-tree `first(of: .returnType)`: a closure parameter's
    /// return type comes first in that walk, which went wrong both ways —
    /// AppKit's non-failable
    /// `NSCollectionViewDiffableDataSource.init(collectionView:itemProvider:)`
    /// (its item provider returns `NSCollectionViewItem?`) printed as
    /// `init?`, and SwiftUI's failable `CoreDisplayLink.init?(displayID:handler:)`
    /// (its handler returns `()`) as `init`.
    var initFailabilityKind: InitFailabilityKind {
        guard let resultType = declaredFunctionType?.children.first(of: .returnType)?.children.first,
              let resultWrapping = resultType.optionalWrapping else {
            return .none
        }
        // An initializer declared on `Optional` itself — `Optional.init(_:)`,
        // SwiftUI's `extension Optional { init(if:then:) }` — returns
        // `Wrapped?` because that is its Self; only a failable one wraps it
        // once more.
        if isDeclaredOnOptional, resultWrapping.wrappedType.optionalWrapping == nil {
            return .none
        }
        return resultWrapping.kind
    }

    var isReturnOptional: Bool {
        initFailabilityKind == .optional
    }

    /// Whether the member this node declares belongs to `Optional`, directly
    /// or through an extension of it.
    private var isDeclaredOnOptional: Bool {
        guard var declaringType = children.first else { return false }
        if declaringType.kind == .extension, let extendedType = declaringType.children.at(1) {
            declaringType = extendedType
        }
        return declaringType.optionalKind != nil
    }

    /// For a `type` node spelling `Optional<Wrapped>` (or the legacy
    /// `ImplicitlyUnwrappedOptional<Wrapped>`): which of the two, and the
    /// `type` node of `Wrapped`.
    private var optionalWrapping: (kind: InitFailabilityKind, wrappedType: Node)? {
        guard let boundGenericEnum = children.first,
              boundGenericEnum.isKind(of: .boundGenericEnum),
              let enumNode = boundGenericEnum.children.first?.children.first,
              let wrappingKind = enumNode.optionalKind,
              let wrappedType = boundGenericEnum.children.at(1)?.children.first else {
            return nil
        }
        return (wrappingKind, wrappedType)
    }

    /// `.optional` for the `Swift.Optional` enum node,
    /// `.implicitlyUnwrappedOptional` for `Swift.ImplicitlyUnwrappedOptional`,
    /// `nil` for anything else.
    private var optionalKind: InitFailabilityKind? {
        guard kind == .enum,
              let moduleChild = children.first,
              moduleChild.kind == .module,
              moduleChild.text == "Swift",
              let identifierChild = children.at(1),
              identifierChild.kind == .identifier else {
            return nil
        }
        switch identifierChild.text {
        case "Optional":
            return .optional
        case "ImplicitlyUnwrappedOptional":
            return .implicitlyUnwrappedOptional
        default:
            return nil
        }
    }

    /// The function type a function-shaped node declares: the child of its
    /// `type` child, reached through the `dependentGenericType` wrapper a
    /// generic context puts around it.
    private var declaredFunctionType: Node? {
        guard var functionType = children.first(of: .type)?.children.first else { return nil }
        if functionType.kind == .dependentGenericType, let genericFunctionType = functionType.children.first(of: .type)?.children.first {
            functionType = genericFunctionType
        }
        return functionType
    }
}
