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

    /// `@objc protocol` — emits no Swift protocol descriptor: only an ObjC
    /// protocol record in `__objc_protolist` and a field descriptor of kind
    /// `ObjCProtocol` (evolution proposal `swift-declared-objc-protocols`).
    @objc public protocol ObjCProto {
        @objc func ping()
    }

    /// Class conforming to an `@objc protocol` — an ObjC protocol has no
    /// witness table, so no conformance descriptor records it; the class's
    /// `class_ro_t` protocol list does.
    @objc(SymbolTestsCoreObjCBridgeWithProto)
    public class ObjCBridgeWithProto: NSObject, ObjCProto {
        public override init() { super.init() }
        public func ping() {}
    }
}
