import Foundation
import MachOFoundation
@testable import MachOSwiftSection

/// The three async function pointer records the baseline generator and the
/// Suite both work from, loaded once so they cannot drift apart.
package struct AsyncFunctionPointerFixtureRecords {
    package let globalFunction: AsyncFunctionPointer
    package let vtableMethod: AsyncFunctionPointer
    package let distributedThunk: AsyncFunctionPointer

    package init(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        globalFunction = try BaselineFixturePicker.asyncFunctionPointer_globalFunction(in: machO)
        vtableMethod = try BaselineFixturePicker.asyncFunctionPointer_vtableMethod(in: machO)
        distributedThunk = try BaselineFixturePicker.asyncFunctionPointer_distributedThunk(in: machO)
    }
}
