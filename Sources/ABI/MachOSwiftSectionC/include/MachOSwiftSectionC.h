//
//  MachOSwiftSectionC.h
//  MachOSwiftSectionC
//
//  The module's umbrella header: every header in this directory, and a new
//  one goes here too (MachOSwiftSectionCUmbrellaHeaderTests checks).
//
//  Without it, SwiftPM and Tuist give the module the whole directory as its
//  umbrella. A header added to the directory then changes no file a
//  prebuilt module recorded, so Xcode keeps reusing the module built before
//  it and Swift reports the new declarations as not in scope. Listing the
//  header here edits this file, which rebuilds the module.
//

#ifndef MACHO_SWIFT_SECTION_C_H
#define MACHO_SWIFT_SECTION_C_H

#include "CallAccessor.h"
#include "Functions.h"
#include "ValueWitnessTable.h"

#endif
