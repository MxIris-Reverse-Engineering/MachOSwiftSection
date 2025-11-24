//
//  PtrAuthWrapper.h
//  MachOSwiftSection
//
//  Created by JH on 2025/11/24.
//

#ifndef PtrAuthWrapper_h
#define PtrAuthWrapper_h

#include <stdint.h>

typedef enum {
    PtrAuthKeyASIA = 0,
    PtrAuthKeyASIB = 1,
    PtrAuthKeyASDA = 2,
    PtrAuthKeyASDB = 3
} PtrAuthKey;

void * _Nonnull PtrAuth_sign(void * _Nonnull ptr, PtrAuthKey key, uint64_t discriminator);
void * _Nonnull PtrAuth_strip(void * _Nonnull ptr, PtrAuthKey key);
uint64_t PtrAuth_blend(void * _Nonnull ptr, uint64_t discriminator);

#endif /* PtrAuthWrapper_h */

