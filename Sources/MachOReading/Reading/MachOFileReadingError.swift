import MachOExtensions

package enum MachOFileReadingError: Error {
    case invalidDataSize
    case invalidLayoutSize
}

extension MachONamespace {
    func throwIfInvalid(_ isValid: Bool, error: MachOFileReadingError) throws {
        if !isValid {
            throw error
        }
    }
}
