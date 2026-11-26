"""Builds the independent ground truth of the cross-reference recall
benchmark and picks its targets, exactly as the 2026-11-18 IDA / Binary Ninja
benchmark did (see README.md): from `otool -tV`, a linear `adrp` register
tracker, `dyld_info -fixups`, the relative method lists and `__swift5_types` —
none of the tools measured.

The order matters and is kept: a first ground truth with a 64-instruction
window between `adrp` and its use, the Finder targets picked from it, then
the final ground truth without the window, and the ControlCenter targets
picked from that. Both pickings are seeded, so the targets come out the same
every time; `verify_reproduction.py` checks that they do.

Reads `<binary>.otool`, `<binary>.sections` and `<binary>.fixups`
(`prepare.sh`) from the work directory; writes `<binary>.ground-truth.json`,
`<binary>.pairs.json` and `<binary>.targets.json` there.
"""
import collections
import json
import os
import random
import re
import struct
import subprocess

WORK = os.environ.get("CROSS_REFERENCE_RECALL_WORK", "/tmp/cross-reference-recall") + "/"
BINARIES = ("Finder", "ControlCenter")
INSTRUCTION_PATTERN = re.compile(r'^([0-9a-f]{16})\t(\S+)\t?([^;]*)')
ADD_PATTERN = re.compile(r'(\w+), (\w+), #(0x[0-9a-f]+|\d+)$')
MEMORY_PATTERN = re.compile(r'(\w+)(?:, (\w+))?, \[(\w+)(?:, #(-?0x[0-9a-f]+|-?\d+))?\]$')
NOT_WRITING_PREFIXES = ("st", "cmp", "cmn", "tst", "b", "cb", "tb", "ret", "pac", "aut", "brk", "fcmp", "prfm")
POINTER_SECTIONS = ("__got", "__auth_got", "__objc_superrefs", "__objc_classrefs")


def function_starts(binary_name):
    output = subprocess.run(["dyld_info", "-function_starts", WORK + binary_name], capture_output=True, text=True).stdout
    return [int(line.split()[0], 16) for line in output.splitlines()[2:] if line.strip().startswith("0x")]


def file_bytes_reader(binary_name):
    """A reader of the bytes at a virtual address, through the segments'
    file offsets."""
    file_bytes = open(WORK + binary_name, "rb").read()
    load_commands = subprocess.run(["otool", "-l", WORK + binary_name], capture_output=True, text=True).stdout
    segments = []
    current = {}
    for line in load_commands.splitlines():
        tokens = line.split()
        if not tokens:
            continue
        if tokens[0] == "cmd":
            current = {"cmd": tokens[1]}
        if tokens[0] in ("segname", "vmaddr", "vmsize", "fileoff", "filesize") and current.get("cmd") == "LC_SEGMENT_64" and tokens[0] not in current:
            current[tokens[0]] = tokens[1] if tokens[0] == "segname" else int(tokens[1], 0)
            if tokens[0] == "filesize":
                segments.append(dict(current))

    def read_bytes(address, count):
        for segment in segments:
            if segment["vmaddr"] <= address < segment["vmaddr"] + segment["filesize"]:
                offset = segment["fileoff"] + address - segment["vmaddr"]
                return file_bytes[offset:offset + count]
        return None

    return read_bytes


def read_sections(binary_name):
    sections = {}
    for line in open(WORK + binary_name + ".sections"):
        segment, section, address, size = line.split()
        sections[section if section not in sections else segment + "," + section] = (int(address, 16), int(size, 16))
    return sections


def read_fixups(binary_name):
    fixups = {}
    for line in open(WORK + binary_name + ".fixups"):
        tokens = line.split()
        if len(tokens) >= 5 and tokens[2].startswith("0x"):
            address = int(tokens[2], 16)
            if tokens[3] in ("rebase", "auth-rebase"):
                fixups[address] = ("r", int(tokens[4], 16))
            else:
                fixups[address] = ("b", tokens[4])
    return fixups


def track_references(binary_name, window):
    """Every address an instruction reaches: a branch target, an `adr`, or an
    `adrp` page plus the immediate of an `add` or a load / store that uses
    it — no further than `window` instructions apart when a window is given.
    Also which `adrp` each such use pairs with."""
    starts = set(function_starts(binary_name))
    references = collections.defaultdict(list)
    pairs = {}
    registers = {}
    instruction_number = 0
    for line in open(WORK + binary_name + ".otool"):
        match = INSTRUCTION_PATTERN.match(line)
        if not match:
            continue
        instruction_address = int(match.group(1), 16)
        mnemonic = match.group(2)
        operands = match.group(3).strip()
        if instruction_address in starts:
            registers = {}
        instruction_number += 1
        if mnemonic == "adrp":
            registers[operands.split(",", 1)[0].strip()] = (int(line.split(";")[1].strip(), 16), instruction_number, instruction_address)
            continue
        if mnemonic in ("bl", "b") and operands.startswith("0x"):
            references[int(operands, 16)].append((instruction_address, "call" if mnemonic == "bl" else "jump"))
            continue
        if mnemonic == "adr":
            register, immediate = [operand.strip() for operand in operands.split(",")]
            references[instruction_address + int(immediate.lstrip("#"), 0)].append((instruction_address, "adr"))
            registers.pop(register, None)
            continue
        add_match = ADD_PATTERN.match(operands) if mnemonic == "add" else None
        if add_match:
            destination, source, immediate = add_match.groups()
            if source in registers and (window is None or instruction_number - registers[source][1] < window):
                references[registers[source][0] + int(immediate, 0)].append((instruction_address, "add"))
                pairs[instruction_address] = registers[source][2]
            registers.pop(destination, None)
            continue
        memory_match = MEMORY_PATTERN.match(operands)
        if memory_match and (mnemonic.startswith("ld") or mnemonic.startswith("st") or mnemonic == "prfm"):
            destination, second_destination, base, immediate = memory_match.groups()
            if base in registers and (window is None or instruction_number - registers[base][1] < window):
                references[registers[base][0] + int(immediate or "0", 0)].append((instruction_address, mnemonic))
                pairs[instruction_address] = registers[base][2]
            if mnemonic.startswith("ld"):
                registers.pop(destination, None)
                if second_destination:
                    registers.pop(second_destination, None)
            continue
        if operands and not mnemonic.startswith(NOT_WRITING_PREFIXES):
            destination = operands.split(",")[0].strip()
            registers.pop(destination, None)
            if destination.startswith("w"):
                registers.pop("x" + destination[1:], None)
    return references, pairs


def objective_c_stubs(sections, fixups, read_bytes):
    """Each `__objc_stubs` stub: its selector reference and selector."""
    def c_string(address):
        bytes_read = read_bytes(address, 512)
        return bytes_read.split(b"\0")[0].decode("utf8", "replace") if bytes_read else None

    stubs = {}
    if "__objc_stubs" not in sections:
        return stubs
    start, size = sections["__objc_stubs"]
    address = start
    while address < start + size:
        first_word, second_word = struct.unpack("<II", read_bytes(address, 8))
        if (first_word & 0x9F000000) == 0x90000000:
            immediate_low = (first_word >> 29) & 3
            immediate_high = (first_word >> 5) & 0x7FFFF
            immediate = (immediate_high << 2) | immediate_low
            if immediate & (1 << 20):
                immediate -= 1 << 21
            page = (address & ~0xFFF) + (immediate << 12)
            offset = ((second_word >> 10) & 0xFFF) * 8
            selector_reference = page + offset
            fixup = fixups.get(selector_reference)
            selector = c_string(fixup[1]) if fixup and fixup[0] == "r" else None
            stubs[address] = (selector_reference, selector)
        address += 32
    return stubs


def save_ground_truth(binary_name, sections, stubs, references, fixups):
    json.dump({
        "sections": sections,
        "stubs": {str(key): value for key, value in stubs.items()},
        "references": {str(key): value for key, value in references.items()},
        "fixups": {str(key): value for key, value in fixups.items()},
    }, open(WORK + binary_name + ".ground-truth.json", "w"))


def load_ground_truth(binary_name):
    ground_truth = json.load(open(WORK + binary_name + ".ground-truth.json"))
    return (
        ground_truth["sections"],
        {int(key): value for key, value in ground_truth["stubs"].items()},
        {int(key): value for key, value in ground_truth["references"].items()},
        {int(key): value for key, value in ground_truth["fixups"].items()},
    )


def method_list_references(sections, read_bytes):
    """Each method implementation's address, and the method list fields
    that point at it: relative method lists, 12-byte entries."""
    method_lists_start, method_lists_size = sections["__objc_methlist"]
    references = {}
    lists = 0
    address = method_lists_start
    while address < method_lists_start + method_lists_size - 8:
        entry_size_and_flags, count = struct.unpack("<II", read_bytes(address, 8))
        if entry_size_and_flags == 0:
            address += 4
            continue
        if (entry_size_and_flags & 0xFFFC) != 12 or not (entry_size_and_flags & 0x80000000) or count > 5000:
            print("bad method list", hex(address), hex(entry_size_and_flags), count)
            break
        lists += 1
        for index in range(count):
            field = address + 8 + index * 12 + 8
            implementation = field + struct.unpack("<i", read_bytes(field, 4))[0]
            references.setdefault(implementation, []).append(field)
        address += 8 + count * 12
    return references, lists


def pick_finder_targets():
    binary_name = "Finder"
    sections, stubs, references, fixups = load_ground_truth(binary_name)

    def section_range(name):
        start, size = sections[name]
        return start, start + size

    text = section_range("__text")

    def is_in_text(address):
        return text[0] <= address < text[1]

    def code_references(target):
        return sorted(set(instruction for instruction, kind in references.get(target, []) if is_in_text(instruction)))

    targets = {}
    random.seed(7)
    candidates = []
    for stub_address, (selector_reference, selector) in stubs.items():
        calls = [instruction for instruction, kind in references.get(stub_address, []) if kind == "call" and is_in_text(instruction)]
        if 2 <= len(calls) <= 50:
            candidates.append((stub_address, selector_reference, selector, len(calls), len(code_references(selector_reference))))
    with_direct_loads = [candidate for candidate in candidates if candidate[4] > 0]
    chosen = random.sample(candidates, 6) + random.sample(with_direct_loads, 2)
    targets["A"] = [dict(stub=candidate[0], selector_reference=candidate[1], selector=candidate[2]) for candidate in chosen]
    global_offset_table = section_range("__got")
    authenticated_global_offset_table = section_range("__auth_got")
    class_list = section_range("__objc_classlist")
    external = [
        (address, value) for address, (kind, value) in fixups.items()
        if (global_offset_table[0] <= address < global_offset_table[1] or authenticated_global_offset_table[0] <= address < authenticated_global_offset_table[1])
        and kind == "b" and "_OBJC_CLASS_$_" in value and 2 <= len(code_references(address)) <= 50
    ]
    classes = [value for address, (kind, value) in fixups.items() if class_list[0] <= address < class_list[1] and kind == "r"]
    own = [class_address for class_address in classes if 2 <= len(code_references(class_address)) <= 50]
    targets["B"] = [dict(kind="ext", slot=address, symbol=value) for address, value in random.sample(external, 4)] + [dict(kind="own", class_address=class_address) for class_address in random.sample(own, 4)]
    authenticated_stubs = section_range("__auth_stubs")
    targets["C"] = random.sample([address for address in range(authenticated_stubs[0], authenticated_stubs[1], 16) if 2 <= len(code_references(address)) <= 50], 8)
    starts = function_starts(binary_name)
    start_set = set(starts)
    targets["D"] = random.sample([start for start in starts if 2 <= len([instruction for instruction, kind in references.get(start, []) if kind == "call"]) <= 50], 8)
    constant_strings = section_range("__cfstring")
    c_strings = section_range("__cstring")
    constant_string_targets = [address for address in range(constant_strings[0], constant_strings[1], 32) if 2 <= len(code_references(address)) <= 50]
    c_string_targets = sorted(target for target in references if c_strings[0] <= target < c_strings[1] and 2 <= len(code_references(target)) <= 50)
    targets["E"] = [dict(kind="cfstr", address=address) for address in random.sample(constant_string_targets, 4)] + [dict(kind="cstr", address=address) for address in random.sample(c_string_targets, 4)]
    instance_variables = section_range("__objc_ivar")
    targets["F"] = random.sample([address for address in range(instance_variables[0], instance_variables[1], 8) if 2 <= len(code_references(address)) <= 50], 8)
    implementations, lists = method_list_references(sections, file_bytes_reader(binary_name))
    print("lists", lists, "imps", len(implementations))
    rebase_targets_in_text = {}
    for fixup_address, (kind, value) in fixups.items():
        if kind == "r" and is_in_text(value):
            rebase_targets_in_text.setdefault(value, []).append(fixup_address)
    method_implementations = [start for start in implementations if start in start_set]
    pointed_functions = [start for start in rebase_targets_in_text if start in start_set and start not in implementations]
    print("H1", len(method_implementations), "H2", len(pointed_functions))
    targets["H"] = [dict(kind="imp", function=start) for start in random.sample(method_implementations, 4)] + [dict(kind="ptr", function=start) for start in random.sample(pointed_functions, 4)]
    json.dump({
        "targets": targets,
        "method_list_references": {str(key): value for key, value in implementations.items()},
    }, open(WORK + binary_name + ".targets.json", "w"))


def pick_control_center_targets():
    binary_name = "ControlCenter"
    sections, stubs, references, fixups = load_ground_truth(binary_name)
    read_bytes = file_bytes_reader(binary_name)

    def section_range(name):
        start, size = sections[name]
        return start, start + size

    text = section_range("__text")

    def is_in_text(address):
        return text[0] <= address < text[1]

    def section_name(address):
        for name, (start, size) in sections.items():
            if start <= address < start + size:
                return name
        return "?"

    def code_references(target):
        return sorted(set(instruction for instruction, kind in references.get(target, []) if is_in_text(instruction)))

    random.seed(11)
    targets = {}
    candidates = [
        (stub_address, selector_reference, selector, len([instruction for instruction, kind in references.get(stub_address, []) if kind == "call" and is_in_text(instruction)]), len(code_references(selector_reference)))
        for stub_address, (selector_reference, selector) in stubs.items()
    ]
    candidates = [candidate for candidate in candidates if 2 <= candidate[3] <= 50]
    with_direct_loads = [candidate for candidate in candidates if candidate[4] > 0]
    print("A", len(candidates), len(with_direct_loads))
    chosen = random.sample(candidates, 8 - min(2, len(with_direct_loads))) + random.sample(with_direct_loads, min(2, len(with_direct_loads)))
    targets["A"] = [dict(stub=candidate[0], selector_reference=candidate[1], selector=candidate[2]) for candidate in chosen]
    binds_by_symbol = collections.defaultdict(list)
    rebases_by_target = collections.defaultdict(list)
    for address, (kind, value) in fixups.items():
        if kind == "b":
            binds_by_symbol[value.split("/")[-1].split()[0]].append(address)
        else:
            rebases_by_target[value].append(address)
    external = [
        symbol for symbol, slots in binds_by_symbol.items()
        if "_OBJC_CLASS_$_" in symbol and 2 <= sum(len(code_references(slot)) for slot in slots if section_name(slot) in POINTER_SECTIONS) <= 50
    ]
    class_list = section_range("__objc_classlist")
    classes = [value for address, (kind, value) in fixups.items() if class_list[0] <= address < class_list[1] and kind == "r"]

    def class_references(class_address):
        return set(code_references(class_address)).union(*[set(code_references(slot)) for slot in rebases_by_target.get(class_address, []) if section_name(slot) in POINTER_SECTIONS])

    own = [class_address for class_address in classes if 2 <= len(class_references(class_address)) <= 50]
    print("B ext", len(external), "own", len(own), "of", len(classes))
    targets["B"] = [dict(kind="ext", symbol="x/" + symbol) for symbol in random.sample(external, 4)] + [dict(kind="own", class_address=class_address) for class_address in random.sample(own, min(4, len(own)))]
    authenticated_stubs = section_range("__auth_stubs")
    targets["C"] = random.sample([address for address in range(authenticated_stubs[0], authenticated_stubs[1], 16) if 2 <= len(code_references(address)) <= 50], 8)
    starts = function_starts(binary_name)
    start_set = set(starts)
    types = section_range("__swift5_types")
    accessors = {}
    for address in range(types[0], types[1], 4):
        descriptor = address + struct.unpack("<i", read_bytes(address, 4))[0]
        flags = struct.unpack("<I", read_bytes(descriptor, 4))[0]
        kind = flags & 0x1F
        if kind in (16, 17, 18):
            accessor = descriptor + 12 + struct.unpack("<i", read_bytes(descriptor + 12, 4))[0]
            accessors[accessor] = kind
    accessor_candidates = [accessor for accessor in accessors if accessor in start_set and 2 <= len([instruction for instruction, kind in references.get(accessor, []) if kind == "call"]) <= 50]
    print("accessors", len(accessors), "cand", len(accessor_candidates))
    internal = [start for start in starts if start not in accessors and 2 <= len([instruction for instruction, kind in references.get(start, []) if kind == "call"]) <= 50]
    targets["D"] = random.sample(internal, 8)
    c_strings = section_range("__cstring")
    c_string_targets = sorted(target for target in references if c_strings[0] <= target < c_strings[1] and 2 <= len(code_references(target)) <= 50)
    targets["E"] = [dict(kind="cstr", address=address) for address in random.sample(c_string_targets, 8)]
    constant_strings = section_range("__cfstring")
    print("cfstrings", [(hex(address), len(code_references(address))) for address in range(constant_strings[0], constant_strings[1], 32)])
    instance_variables = section_range("__objc_ivar")
    targets["F"] = [address for address in range(instance_variables[0], instance_variables[1], 4) if len(code_references(address)) >= 1]
    print("F", [(hex(address), len(code_references(address))) for address in targets["F"]])
    implementations, _ = method_list_references(sections, read_bytes)
    rebase_targets_in_text = {}
    for fixup_address, (kind, value) in fixups.items():
        if kind == "r" and is_in_text(value):
            rebase_targets_in_text.setdefault(value, []).append(fixup_address)
    method_implementations = [start for start in implementations if start in start_set]
    # Functions referenced only from Swift metadata and witness tables: data,
    # and no code.
    table_only = [
        start for start, slots in rebase_targets_in_text.items()
        if start in start_set and start not in implementations and not code_references(start) and all(section_name(slot) in ("__data", "__const") for slot in slots)
    ]
    pointed_functions = [start for start in rebase_targets_in_text if start in start_set and start not in implementations and start not in table_only]
    print("H1", len(method_implementations), "H2", len(pointed_functions), "G2", len(table_only))
    targets["H"] = [dict(kind="imp", function=start) for start in random.sample(method_implementations, 4)] + [dict(kind="ptr", function=start) for start in random.sample(pointed_functions, 4)]
    targets["G"] = [dict(category="G", kind="accessor", function=start) for start in random.sample(accessor_candidates, 8)] + [dict(category="G", kind="tableonly", function=start) for start in random.sample(table_only, 8)]
    json.dump({
        "targets": targets,
        "method_list_references": {str(key): value for key, value in implementations.items()},
    }, open(WORK + binary_name + ".targets.json", "w"))


def main():
    for binary_name in BINARIES:
        read_bytes = file_bytes_reader(binary_name)
        sections = read_sections(binary_name)
        fixups = read_fixups(binary_name)
        stubs = objective_c_stubs(sections, fixups, read_bytes)
        references, _ = track_references(binary_name, window=64)
        save_ground_truth(binary_name, sections, stubs, references, fixups)
        print(binary_name, "stubs", len(stubs), "targets", len(references), "refs", sum(len(value) for value in references.values()))
    pick_finder_targets()
    for binary_name in BINARIES:
        sections, stubs, first_references, fixups = load_ground_truth(binary_name)
        references, pairs = track_references(binary_name, window=None)
        save_ground_truth(binary_name, sections, stubs, references, fixups)
        json.dump({str(key): value for key, value in pairs.items()}, open(WORK + binary_name + ".pairs.json", "w"))
        print(binary_name, "refs old", sum(len(value) for value in first_references.values()), "new", sum(len(value) for value in references.values()))
    pick_control_center_targets()


main()
