import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import MemberwiseInit
import Demangling

@MemberwiseInit(.package)
package struct DumperConfiguration {
    package var demangleResolver: DemangleResolver
    package var indentation: Int = 1
    package var displayParentName: Bool = true
    package var emitOffsetComments: Bool = false
}
