import Foundation
@_spi(Internals) import MachOCaches
import MachOSwiftSection

package final class PrimitiveTypeMappingCache: SharedCache<PrimitiveTypeMapping>, @unchecked Sendable {
    package static let shared = PrimitiveTypeMappingCache()

    private override init() {
        super.init()
    }

    package override func buildStorage<MachO>(for machO: MachO) -> PrimitiveTypeMapping? where MachO: MachORepresentableWithCache {
        if let machO = machO as? any MachOSwiftSectionRepresentableWithCache {
            return try? .init(machO: machO)
        } else {
            return nil
        }
    }

    package override func storage<MachO>(in machO: MachO) -> PrimitiveTypeMapping? where MachO: MachORepresentableWithCache {
        super.storage(in: machO)
    }
}
