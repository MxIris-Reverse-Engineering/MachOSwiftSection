import Foundation

public enum DependentTypeAccess {
    // Custom protocol hierarchy with no same-type constraints so that
    // dependent member type chains survive through compilation instead
    // of being canonicalized away (as happens with Collection/Sequence,
    // where Iterator.Element == Element, Indices.Element == Index, etc.).
    public protocol OuterProtocol {
        associatedtype Middle: MiddleProtocol
        associatedtype Inner: InnerProtocol
    }

    public protocol MiddleProtocol {
        associatedtype Leaf
        associatedtype Branch: BranchProtocol
    }

    public protocol BranchProtocol {
        associatedtype Final
    }

    public protocol InnerProtocol {
        associatedtype Value
    }

    // Two-level dependent member type access: A.Middle.Leaf, A.Inner.Value.
    public struct DependentAccessTest<Element: OuterProtocol> {
        public var middleLeaf: Element.Middle.Leaf?
        public var innerValue: Element.Inner.Value?

        public init(
            middleLeaf: Element.Middle.Leaf?,
            innerValue: Element.Inner.Value?
        ) {
            self.middleLeaf = middleLeaf
            self.innerValue = innerValue
        }
    }

    // Three-level dependent member type access: A.Middle.Branch.Final.
    public struct DeepDependentAccessTest<Element: OuterProtocol> {
        public var branchFinal: Element.Middle.Branch.Final?

        public init(branchFinal: Element.Middle.Branch.Final?) {
            self.branchFinal = branchFinal
        }
    }

    // Dependent member types in function parameter and return position.
    public struct DependentFunctionTest {
        public func acceptDependent<Element: OuterProtocol>(
            _ element: Element,
            middleLeaf: Element.Middle.Leaf,
            innerValue: Element.Inner.Value
        ) -> Element.Middle.Branch.Final? {
            nil
        }
    }

    // Protocol carrying a same-type requirement between dependent member
    // types — this exercises the `where` clause mangling, not canonicalization.
    public protocol DependentProtocol {
        associatedtype First
        associatedtype Second: MiddleProtocol where Second.Leaf == First
    }
}
