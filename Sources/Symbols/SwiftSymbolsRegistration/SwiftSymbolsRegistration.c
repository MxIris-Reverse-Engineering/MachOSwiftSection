//
//  SwiftSymbolsRegistration.c
//  SwiftSymbolsRegistration
//
//  Registers `SymbolLanguage.swift` with MachOKitExtensions' symbol language
//  registry when the image holding SwiftSymbols loads, so that every
//  classification and the C/C++ symbol index see the language before any
//  code asks. Swift has no load-time initializers; a constructor here, in a
//  C target SwiftSymbols depends on, runs with no caller involved.
//

#include "SwiftSymbolsRegistration.h"

// Defined in SwiftSymbols with `@c`.
extern void swift_symbols_register_symbol_language(void);

__attribute__((constructor))
static void registerSymbolLanguageAtLoad(void) {
    swift_symbols_register_symbol_language();
}
