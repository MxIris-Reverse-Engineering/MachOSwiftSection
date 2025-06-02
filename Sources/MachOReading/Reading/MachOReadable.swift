import MachOKit
import MachOExtensions

package protocol MachOReadable {
    func readElement<Element>(offset: Int) throws -> Element

    func readWrapperElement<Element>(offset: Int) throws -> Element where Element: LocatableLayoutWrapper

    func readElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element]

    func readWrapperElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper

    func readString(offset: Int) throws -> String
}

