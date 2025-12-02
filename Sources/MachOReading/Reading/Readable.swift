import MachOKit
import MachOExtensions

public protocol Readable {
    func readElement<Element>(offset: Int) throws -> Element

    func readWrapperElement<Element>(offset: Int) throws -> Element where Element: LocatableLayoutWrapper

    func readElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element]

    func readWrapperElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper

    func readString(offset: Int) throws -> String
    
    func resolveOffset(at address: UInt64) -> Int
    
    func stripPointerTags(of rawVMAddr: UInt64) -> UInt64
}


//public protocol InProcessReadable {
//    func readElement<Element>() throws -> Element
//
//    func readWrapperElement<Element>() throws -> Element where Element: LocatableLayoutWrapper
//
//    func readElements<Element>(to: Element.Type, numberOfElements: Int) throws -> [Element]
//
//    func readElements<Element>(numberOfElements: Int) throws -> [Element]
//    
//    func readWrapperElements<Element>(to: Element.Type, numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper
//
//    func readWrapperElements<Element>(numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper
//
//    func readString() throws -> String
//}
