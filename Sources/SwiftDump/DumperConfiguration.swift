import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import MemberwiseInit
import Demangling

@MemberwiseInit(.public)
public struct DumperConfiguration: Sendable {
    public var demangleResolver: DemangleResolver
    public var indentation: Int = 1
    public var displayParentName: Bool = true
    public var emitOffsetComments: Bool = false

    public static func demangleOptions(_ demangleOptions: DemangleOptions) -> Self {
        .init(demangleResolver: .options(demangleOptions))
    }
}
