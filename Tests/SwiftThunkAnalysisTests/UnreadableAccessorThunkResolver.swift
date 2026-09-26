import MachOKit
import SwiftDeclarationRendering
import SwiftThunkAnalysis

/// A resolver that reads nothing — what every thunk looks like to a reader
/// that does not recognize its shape. Scoped through
/// `AccessorThunkResolution.$taskResolver` to pin the placeholder rendering
/// (`accessor function at N` inside its type) now that the disassembling
/// resolver is the default for every task.
struct UnreadableAccessorThunkResolver: AccessorThunkResolving {
    func underlyingTypes(forAccessorThunkAt offset: Int, in machO: MachOFile, ownerLayout: AccessorThunkOwnerLayout) -> [ConditionalUnderlyingType] {
        []
    }
}
