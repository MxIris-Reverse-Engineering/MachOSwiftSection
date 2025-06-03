import MachOKit

package protocol MachORepresentableWithCache: MachORepresentable {
    var cache: DyldCache? { get }
}

extension MachOFile: MachORepresentableWithCache {}

extension MachOImage: MachORepresentableWithCache {
    package var cache: DyldCache? { nil }
}
