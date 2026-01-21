//
//  ValueWitnessTable.c
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

#if defined(__arm64e__)

#include "ValueWitnessTable.h"

// VWT functions.

void *swift_section_vwt_initializeBufferWithCopyOfBuffer(const void *ptr, void *dest,
                                                void *src,
                                                const void *metadata) {
  const ValueWitnessTable *vwt = (const ValueWitnessTable *)ptr;
  return vwt->initializeBufferWithCopyOfBuffer(dest, src, metadata);
}

void swift_section_vwt_destroy(const void *ptr, void *value, const void *metadata) {
  const ValueWitnessTable *vwt = (const ValueWitnessTable *)ptr;
  return vwt->destroy(value, metadata);
}

void *swift_section_vwt_initializeWithCopy(const void *ptr, void *dest, void *src,
                                  const void *metadata) {
  const ValueWitnessTable *vwt = (const ValueWitnessTable *)ptr;
  return vwt->initializeWithCopy(dest, src, metadata);
}

void *swift_section_vwt_assignWithCopy(const void *ptr, void *dest, void *src,
                              const void *metadata) {
  const ValueWitnessTable *vwt = (const ValueWitnessTable *)ptr;
  return vwt->assignWithCopy(dest, src, metadata);
}

void *swift_section_vwt_initializeWithTake(const void *ptr, void *dest, void *src,
                                  const void *metadata) {
  const ValueWitnessTable *vwt = (const ValueWitnessTable *)ptr;
  return vwt->initializeWithTake(dest, src, metadata);
}

void *swift_section_vwt_assignWithTake(const void *ptr, void *dest, void *src,
                              const void *metadata) {
  const ValueWitnessTable *vwt = (const ValueWitnessTable *)ptr;
  return vwt->assignWithTake(dest, src, metadata);
}

unsigned swift_section_vwt_getEnumTagSinglePayload(const void *ptr, const void *instance,
                                          unsigned numEmptyCases,
                                          const void *metadata) {
  const ValueWitnessTable *vwt = (const ValueWitnessTable *)ptr;
  return vwt->getEnumTagSinglePayload(instance, numEmptyCases, metadata);
}

void swift_section_vwt_storeEnumTagSinglePayload(const void *ptr, void *instance,
                                        unsigned tag, unsigned numEmptyCases,
                                        const void *metadata) {
  const ValueWitnessTable *vwt = (const ValueWitnessTable *)ptr;
  return vwt->storeEnumTagSinglePayload(instance, tag, numEmptyCases, metadata);
}

// Enum VWT functions

unsigned swift_section_vwt_getEnumTag(const void *ptr, const void *instance,
                             const void *metadata) {
  const EnumValueWitnessTable *vwt = (const EnumValueWitnessTable *)ptr;
  return vwt->getEnumTag(instance, metadata);
}

void swift_section_vwt_destructiveProjectEnumData(const void *ptr, void *instance,
                                         const void *metadata) {
  const EnumValueWitnessTable *vwt = (const EnumValueWitnessTable *)ptr;
  return vwt->destructiveProjectEnumData(instance, metadata);
}

void swift_section_vwt_destructiveInjectEnumTag(const void *ptr, void *instance,
                                       unsigned tag,
                                       const void *metadata) {
  const EnumValueWitnessTable *vwt = (const EnumValueWitnessTable *)ptr;
  return vwt->destructiveInjectEnumTag(instance, tag, metadata);
}

#endif // defined(__arm64e__)
