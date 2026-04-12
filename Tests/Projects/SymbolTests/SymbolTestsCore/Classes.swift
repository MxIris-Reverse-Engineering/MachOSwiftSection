import Foundation
import SymbolTestsHelper

public enum Classes {
    public class ExternalSwiftSubclassTest: Object {
        public override func instanceMethod() -> String {
            "xxxxxxxxxxxxx"
        }
    }

    public class ExternalObjCSubclassTest: NSObject {
        public override func isKind(of aClass: AnyClass) -> Bool {
            return true
        }
    }

    public class ClassTest {
        public var instanceVariable: Bool {
            set {}
            get { false }
        }

        public func instanceMethod() -> Self { self }

        public dynamic var dynamicVariable: Bool {
            set {}
            get { false }
        }

        public dynamic func dynamicMethod() {}
    }

    public class SubclassTest: ClassTest {
        public override final var instanceVariable: Bool {
            set {}
            get { true }
        }

        public override func instanceMethod() -> Self { self }

        public override var dynamicVariable: Bool {
            set {}
            get { true }
        }

        public override func dynamicMethod() {}
    }

    public final class FinalClassTest: SubclassTest {
        public override func instanceMethod() -> Self { self }

        public override var dynamicVariable: Bool {
            set {}
            get { true }
        }

        public override func dynamicMethod() {}
    }

    public class StoredPropertiesTest {
        public let constantProperty: String
        public var variableProperty: Int
        public weak var weakDelegate: AnyObject?
        public lazy var lazyProperty: String = "default"

        public init(constantProperty: String, variableProperty: Int) {
            self.constantProperty = constantProperty
            self.variableProperty = variableProperty
        }

        deinit {}
    }

    open class OpenAccessTest {
        open var openProperty: Int {
            get { 0 }
            set {}
        }

        open func openMethod() -> String { "" }

        public func publicMethod() -> Int { 0 }

        public init() {}
    }

    open class OpenAccessSubTest: OpenAccessTest {
        open override var openProperty: Int {
            get { 1 }
            set {}
        }

        open override func openMethod() -> String { "subclass" }
    }

    @objcMembers
    public class ObjCMembersTest: NSObject {
        public var property: Int = 0

        public func method() -> Int { property }
    }
}
