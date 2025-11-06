import MachOKit
import MachOFoundation

public protocol ClassMetadataObjCInteropProtocol: AnyClassMetadataObjCInteropProtocol, FinalClassMetadataProtocol where Layout: ClassMetadataObjCInteropLayout {}

extension AnyClassMetadataObjCInteropProtocol {
    public func superclass<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> AnyClassMetadataObjCInterop? {
        try layout.superclass.resolve(in: machO)
    }

    public var isPureObjC: Bool {
        !isTypeMetadata
    }

    public var isTypeMetadata: Bool {
        layout.data & 2 != 0
    }
}
