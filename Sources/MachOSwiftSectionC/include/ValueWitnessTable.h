//
//  ValueWitnessTable.h
//  Echo
//
//  Based on code originally created by Alejandro Alonso
//  Original Copyright (c) 2021 Alejandro Alonso
//
//  MachOSwiftSectionC
//
//  Modified by Mx-Iris on 2025/12/18.
//  Copyright (c) 2025 Mx-Iris. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

#ifndef VALUE_WITNESS_TABLE_H
#define VALUE_WITNESS_TABLE_H

#if defined(__arm64e__)

#include <stddef.h>
#include <ptrauth.h>

#define VWT_FP(key) __ptrauth_swift_value_witness_function_pointer(key)

// VWT

typedef struct ValueWitnessTable {
  void *(* VWT_FP(0xda4a) initializeBufferWithCopyOfBuffer)(void *, void *,
                                                            const void *);
  void (* VWT_FP(0x04f8) destroy)(void *, const void *);
  void *(* VWT_FP(0xe3ba) initializeWithCopy)(void *, void *, const void *);
  void *(* VWT_FP(0x8751) assignWithCopy)(void *, void *, const void *);
  void *(* VWT_FP(0x48d8) initializeWithTake)(void *, void *, const void *);
  void *(* VWT_FP(0xefda) assignWithTake)(void *, void *, const void *);
  unsigned (* VWT_FP(0x60f0) getEnumTagSinglePayload)(const void *, unsigned,
                                                      const void *);
  void (* VWT_FP(0xa0d1) storeEnumTagSinglePayload)(void *, unsigned, unsigned,
                                                    const void *);
  
  size_t size;
  size_t stride;
  unsigned flags;
  unsigned extraInhabitantCount;
} ValueWitnessTable;

// Enum VWT

typedef struct EnumValueWitnessTable {
  ValueWitnessTable base;
  
  int (* VWT_FP(0xa3b5) getEnumTag)(const void *, const void *);
  void (* VWT_FP(0x041d) destructiveProjectEnumData)(void *, const void *);
  void (* VWT_FP(0xb2e4) destructiveInjectEnumTag)(void *, unsigned,
                                                   const void *);
} EnumValueWitnessTable;

// A note for the following: All of these functions are required for platforms
// that utilize pointer authentication because we need to sign the vwt function
// pointers. We can't import these structs in Swift due to the clang importer
// not importing members who have ptrauth qualifiers. Define these stubs that
// call these functions. The first parameter for all of these stubs is a pointer
// to the VWT.

// VWT functions.

void *swift_section_vwt_initializeBufferWithCopyOfBuffer(const void *, void *, void *,
                                                const void *);
void swift_section_vwt_destroy(const void *, void *, const void *);
void *swift_section_vwt_initializeWithCopy(const void *, void *, void *, const void *);
void *swift_section_vwt_assignWithCopy(const void *, void *, void *, const void *);
void *swift_section_vwt_initializeWithTake(const void *, void *, void *, const void *);
void *swift_section_vwt_assignWithTake(const void *, void *, void *, const void *);
unsigned swift_section_vwt_getEnumTagSinglePayload(const void *, const void *, unsigned,
                                          const void *);
void swift_section_vwt_storeEnumTagSinglePayload(const void *, void *, unsigned, unsigned,
                                        const void *);

// Enum VWT functions

unsigned swift_section_vwt_getEnumTag(const void *, const void *, const void *);
void swift_section_vwt_destructiveProjectEnumData(const void *, void *, const void *);
void swift_section_vwt_destructiveInjectEnumTag(const void *, void *, unsigned,
                                       const void *);

#endif // defined(__arm64e__)

#endif /* VALUE_WITNESS_TABLE_H */
