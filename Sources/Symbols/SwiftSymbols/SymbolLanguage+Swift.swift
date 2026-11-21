import MachOSymbols
import SwiftSymbolsRegistration

extension SymbolLanguage {
    /// A Swift-mangled name (`$s`, `_$s`, `$S`, `_$S`, `$e`, `_$e`, `_T0`,
    /// `@__swiftmacro_`) or a name the Swift compiler emits for the linker to
    /// de-duplicate (`_symbolic `, `_default assoc type `).
    ///
    /// Registered with MachOKitExtensions' `SymbolLanguageRegistry` when the
    /// image holding SwiftSymbols loads, so MachOKitExtensions'
    /// `SymbolIndexStore` keeps only where these symbols sit. Its name,
    /// `"Swift"`, is its identity.
    public static let swift = SymbolLanguage(rawValue: "Swift")
}

/// The rules that tell a Swift symbol name from its leading bytes.
///
/// The mangling prefixes are exactly the ones swift-demangling's
/// `isSwiftSymbol` accepts; `SymbolTableEquivalenceTests` pins the two equal
/// over a real symbol table, so that a prefix the demangler grows does not
/// go unnoticed here. Reading bytes in place keeps a sweep from making a
/// `String` of every name.
enum SwiftSymbolNameRecognition {
    static func recognizes(_ name: UnsafePointer<CChar>) -> Bool {
        switch UInt8(bitPattern: name.pointee) {
        case UInt8(ascii: "$"):
            hasPrefix(name, "$s") || hasPrefix(name, "$S") || hasPrefix(name, "$e")
        case UInt8(ascii: "@"):
            hasPrefix(name, "@__swiftmacro_")
        case UInt8(ascii: "_"):
            hasPrefix(name, "_$s") || hasPrefix(name, "_$S") || hasPrefix(name, "_$e") || hasPrefix(name, "_T0")
                || hasPrefix(name, "_symbolic ") || hasPrefix(name, "_default assoc type ")
        default:
            false
        }
    }

    /// Whether the NUL-terminated `name` starts with `prefix`. Never reads
    /// past the terminator: the prefixes hold no NUL byte, so a shorter name
    /// mismatches at its terminator first.
    private static func hasPrefix(_ name: UnsafePointer<CChar>, _ prefix: StaticString) -> Bool {
        prefix.withUTF8Buffer { prefixBytes in
            for (index, prefixByte) in prefixBytes.enumerated() where UInt8(bitPattern: name[index]) != prefixByte {
                return false
            }
            return true
        }
    }
}

/// Registers ``SymbolLanguage/swift``. `SwiftSymbolsRegistration`'s
/// constructor calls it once, when the image loads.
///
/// Public, behind an SPI nobody imports, only so that its C symbol keeps
/// external linkage. Internal, the symbol is hidden, and Xcode links each
/// package target into a single relocatable object (`ld -r`) first, which
/// turns a hidden symbol local: the constructor, in another target, then
/// fails to link in a Release build ("Undefined symbols:
/// _swift_symbols_register_symbol_language").
@_spi(SymbolLanguageRegistration)
@c(swift_symbols_register_symbol_language)
public func registerSwiftSymbolLanguage() {
    SymbolLanguageRegistry.shared.register(.swift, where: SwiftSymbolNameRecognition.recognizes)
    // Does nothing at run time. The reference is what counts: a static link
    // that loads this file (any use of the Swift symbol index, any link with
    // -ObjC) loads SwiftSymbolsRegistration.c and its constructor with it,
    // which nothing else refers to. See that file.
    swift_symbols_registration_anchor()
}
