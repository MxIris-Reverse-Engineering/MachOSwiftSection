import Foundation
import Testing
import MachOKit

import MachOFoundation

package class MachOImageTests {
    package let machOImage: MachOImage

    package class var imageName: MachOImageName { .Foundation }
        
    package init() async throws {
        self.machOImage = try #require(MachOImage(named: Self.imageName))
    }
}
