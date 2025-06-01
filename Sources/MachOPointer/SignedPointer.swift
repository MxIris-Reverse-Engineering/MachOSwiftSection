import MachOKit
import MachOReading
import MachOExtensions

//public struct SignedPointer<Pointee: Resolvable>: RelativeIndirectType, PointerProtocol {
//    public let address: UInt64
//    
//    public init(address: UInt64) {
//        self.address = address
//    }
//    
//    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
//        if let rebase = machOFile.resolveRebase(fileOffset: fileOffset.cast()) {
//            return .init(address: rebase)
//        } else {
//            return try machOFile.readElement(offset: fileOffset)
//        }
//    }
//}
