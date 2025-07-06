import Foundation
import MachOCaches
import MachOSwiftSection

package final class PrimitiveTypeMappingCache: MachOCache<PrimitiveTypeMapping> {
    package static let shared = PrimitiveTypeMappingCache()

    private override init() {
        super.init()
    }

    package override func buildEntry<MachO>(for machO: MachO) -> PrimitiveTypeMapping? where MachO: MachORepresentableWithCache {
        if let machO = machO as? any MachOSwiftSectionRepresentableWithCache {
            return try? .init(machO: machO)
        } else {
            return nil
        }
    }
}
