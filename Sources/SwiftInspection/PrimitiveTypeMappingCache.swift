import Foundation
@_spi(Internals) import MachOCaches
import MachOSwiftSection

@_spi(Internals)
public final class PrimitiveTypeMappingCache: SharedCache<PrimitiveTypeMapping>, @unchecked Sendable {
    public static let shared = PrimitiveTypeMappingCache()

    private override init() {
        super.init()
    }

    public override func buildStorage<MachO>(for machO: MachO) -> PrimitiveTypeMapping? where MachO: MachORepresentableWithCache {
        if let machO = machO as? any MachOSwiftSectionRepresentableWithCache {
            return try? .init(machO: machO)
        } else {
            return nil
        }
    }

    public override func storage<MachO>(in machO: MachO) -> PrimitiveTypeMapping? where MachO: MachORepresentableWithCache {
        super.storage(in: machO)
    }
}
