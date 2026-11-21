import MachOFixtureSupport

extension MachOImageName {
    /// The SymbolTests fixtures as this process knows them once loaded: the
    /// bare image name `MachOImage(name:)` matches. Their files are the
    /// `MachOFileName` members of the same names.
    package static let SymbolTests: MachOImageName = "SymbolTests"
    package static let SymbolTestsCore: MachOImageName = "SymbolTestsCore"
}
