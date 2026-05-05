import Foundation

// Fixtures producing classes with ObjC interop, surfacing
// AnyClassMetadataObjCInterop, ClassMetadataObjCInterop,
// ObjCClassWrapperMetadata, and ObjC protocol prefix metadata.

public enum ObjCClassWrapperFixtures {
    /// Swift class inheriting NSObject — gets full ObjC interop metadata
    /// (isaPointer, cacheData, etc.) and is surfaced as a Swift type
    /// with `ClassMetadataObjCInterop` shape.
    @objc(SymbolTestsCoreObjCBridgeClass)
    public class ObjCBridge: NSObject {
        public override init() { super.init() }
        @objc public var label: String = "objc"
    }

    /// `@objc protocol` — emits a Swift protocol descriptor with an
    /// `ObjCProtocolPrefix`-typed reference to the underlying ObjC
    /// protocol.
    @objc public protocol ObjCProto {
        @objc func ping()
    }

    /// Class conforming to `@objc protocol` — surfaces `RelativeObjCProtocolPrefix`
    /// in the class's conformance descriptor.
    @objc(SymbolTestsCoreObjCBridgeWithProto)
    public class ObjCBridgeWithProto: NSObject, ObjCProto {
        public override init() { super.init() }
        public func ping() {}
    }
}
