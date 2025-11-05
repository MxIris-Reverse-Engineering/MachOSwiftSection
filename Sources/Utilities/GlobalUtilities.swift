import Foundation

package func align(address: Int, alignment: Int) -> Int {
    (address + alignment - 1) & ~(alignment - 1)
}
