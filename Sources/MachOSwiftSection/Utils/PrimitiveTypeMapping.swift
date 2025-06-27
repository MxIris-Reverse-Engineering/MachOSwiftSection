import Foundation
import MachOFoundation

class PrimitiveTypeMapping<MachO: MachORepresentableWithCache> {
    private let machO: MachO

    init(machO: MachO) throws {
        self.machO = machO
    }
}
