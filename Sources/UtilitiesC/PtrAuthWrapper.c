//
//  PtrAuthWrapper.c
//  MachOSwiftSection
//
//  Created by JH on 2025/11/24.
//

#include "PtrAuthWrapper.h"
#include <ptrauth.h>

void * _Nonnull PtrAuth_sign(void * _Nonnull ptr, PtrAuthKey key, uint64_t discriminator) {
    switch (key) {
        case PtrAuthKeyASIA:
            return ptrauth_sign_unauthenticated(ptr, ptrauth_key_asia, discriminator);
        case PtrAuthKeyASIB:
            return ptrauth_sign_unauthenticated(ptr, ptrauth_key_asib, discriminator);
        case PtrAuthKeyASDA:
            return ptrauth_sign_unauthenticated(ptr, ptrauth_key_asda, discriminator);
        case PtrAuthKeyASDB:
            return ptrauth_sign_unauthenticated(ptr, ptrauth_key_asdb, discriminator);
        default:
            return ptr;
    }
}

void * _Nonnull PtrAuth_strip(void * _Nonnull ptr, PtrAuthKey key) {
    switch (key) {
        case PtrAuthKeyASIA:
            return ptrauth_strip(ptr, ptrauth_key_asia);
        case PtrAuthKeyASIB:
            return ptrauth_strip(ptr, ptrauth_key_asib);
        case PtrAuthKeyASDA:
            return ptrauth_strip(ptr, ptrauth_key_asda);
        case PtrAuthKeyASDB:
            return ptrauth_strip(ptr, ptrauth_key_asdb);
        default:
            return ptr;
    }
}

uint64_t PtrAuth_blend(void * _Nonnull ptr, uint64_t discriminator) {
    return ptrauth_blend_discriminator(ptr, discriminator);
}
