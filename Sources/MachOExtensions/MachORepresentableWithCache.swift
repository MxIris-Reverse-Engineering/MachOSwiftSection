import MachOKit

package protocol MachORepresentableWithCache: MachORepresentable {
    var cache: DyldCache? { get }
    var startOffset: Int { get }
}

extension MachOFile: MachORepresentableWithCache {
    package var startOffset: Int {
        if cache != nil {
            headerStartOffsetInCache
        } else {
            headerStartOffset
        }
    }
}

extension MachOImage: MachORepresentableWithCache {
    package var cache: DyldCache? { nil }
    package var startOffset: Int { 0 }
}
