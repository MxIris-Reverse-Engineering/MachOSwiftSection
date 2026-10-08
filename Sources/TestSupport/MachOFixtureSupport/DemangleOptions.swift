import Foundation
import MachOSwiftSection
import SwiftDump

extension DemangleOptions {
    /// Snapshot/baseline fixtures are recorded with interface-style printing:
    /// optionals sugar to `T?`, arrays to `[T]`, etc. (`.interface` sets
    /// `.synthesizeSugarOnTypes`, which `.default` does not). Keep this on
    /// `.interface` so the recorded `SwiftDumpTests` snapshots stay sugared and
    /// idiomatic — switching to `.default` desugars every optional/array in the
    /// output and breaks the snapshot suite.
    package static let test: DemangleOptions = .interface
}
