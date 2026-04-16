import Foundation

public enum DiamondInheritance {
    public protocol DiamondBaseProtocol {
        func baseMethod() -> String
    }

    public protocol DiamondLeftProtocol: DiamondBaseProtocol {
        func leftMethod() -> Int
    }

    public protocol DiamondRightProtocol: DiamondBaseProtocol {
        func rightMethod() -> Double
    }

    public protocol DiamondBottomProtocol: DiamondLeftProtocol, DiamondRightProtocol {
        func bottomMethod() -> Bool
    }

    public struct DiamondImplementationTest: DiamondBottomProtocol {
        public func baseMethod() -> String { "" }
        public func leftMethod() -> Int { 0 }
        public func rightMethod() -> Double { 0.0 }
        public func bottomMethod() -> Bool { false }

        public init() {}
    }

    public protocol TriDiamondRootProtocol {
        func root() -> String
    }

    public protocol TriDiamondFirstProtocol: TriDiamondRootProtocol {
        func first() -> Int
    }

    public protocol TriDiamondSecondProtocol: TriDiamondRootProtocol {
        func second() -> Int
    }

    public protocol TriDiamondThirdProtocol: TriDiamondRootProtocol {
        func third() -> Int
    }

    public protocol TriDiamondLeafProtocol: TriDiamondFirstProtocol, TriDiamondSecondProtocol, TriDiamondThirdProtocol {
        func leaf() -> Int
    }
}
