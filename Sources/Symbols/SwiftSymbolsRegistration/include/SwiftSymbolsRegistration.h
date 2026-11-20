//
//  SwiftSymbolsRegistration.h
//  SwiftSymbolsRegistration
//
//  The target exists for the constructor in SwiftSymbolsRegistration.c.
//

#ifndef SWIFT_SYMBOLS_REGISTRATION_H
#define SWIFT_SYMBOLS_REGISTRATION_H

/// Does nothing. Calling it makes a static link that loads the caller load
/// SwiftSymbolsRegistration.c — and its constructor — too.
void swift_symbols_registration_anchor(void);

#endif
