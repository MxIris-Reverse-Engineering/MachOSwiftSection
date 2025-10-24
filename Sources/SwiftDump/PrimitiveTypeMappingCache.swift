import Foundation
@_spi(Internals) import MachOCaches
import MachOSwiftSection

package final class PrimitiveTypeMappingCache: MachOCache<PrimitiveTypeMapping>, @unchecked Sendable {
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
    
    package override func entry<MachO>(in machO: MachO) -> PrimitiveTypeMapping? where MachO : MachORepresentableWithCache {
        super.entry(in: machO)
    }
}
