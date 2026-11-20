//
//  SwiftSymbolsRegistration.c
//  SwiftSymbolsRegistration
//
//  Registers `SymbolLanguage.swift` with MachOKitExtensions' symbol
//  language registry when the image holding SwiftSymbols loads, so that
//  every classification and the C/C++ symbol index see the language before
//  any code asks. Swift has no load-time initializers; a constructor here,
//  in a C target SwiftSymbols depends on, runs with no caller involved.
//

#include "SwiftSymbolsRegistration.h"

// Defined in SwiftSymbols with `@c`.
extern void swift_symbols_register_symbol_language(void);

__attribute__((constructor))
static void registerSymbolLanguageAtLoad(void) {
    swift_symbols_register_symbol_language();
}

// A linker that reads SwiftSymbols from a static archive (a Tuist static
// framework, a static library) loads an object only for a symbol something
// refers to, and -ObjC does not load an object that defines no Objective-C
// class or category and no Swift type. The constructor above is static, so
// without this function the object would define nothing and never be loaded:
// the image would run without the Swift symbol language registered. SwiftSymbols
// calls this function from the file that registers the language, which every
// use of the Swift symbol index and every link with -ObjC loads.
void swift_symbols_registration_anchor(void) {}
