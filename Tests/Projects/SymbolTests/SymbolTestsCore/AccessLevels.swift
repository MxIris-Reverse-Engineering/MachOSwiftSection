import Foundation

public enum AccessLevels {
    // Note: `package` access level is omitted because the Xcode target
    // does not configure `-package-name`. `public`, `internal`, `fileprivate`,
    // and `private` are still exercised here.
    public struct PublicAccessLevelTest {
        public var publicField: Int
        internal var internalField: Int
        fileprivate var fileprivateField: Int
        private var privateField: Int

        public init(publicField: Int, internalField: Int, fileprivateField: Int, privateField: Int) {
            self.publicField = publicField
            self.internalField = internalField
            self.fileprivateField = fileprivateField
            self.privateField = privateField
        }

        public func publicMethod() {}
        internal func internalMethod() {}
        fileprivate func fileprivateMethod() {}
        private func privateMethod() {}
    }

    open class OpenAccessLevelTest {
        open var openField: Int = 0
        public var publicField: Int = 0

        open func openMethod() {}
        public func publicMethod() {}

        public init() {}
    }

    public class SubclassOfOpenAccessLevel: OpenAccessLevelTest {
        open override func openMethod() {}
        public override var openField: Int {
            get { 0 }
            set {}
        }
    }
}
