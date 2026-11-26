"""Asks `swift-section refs` about every target of the benchmark.

The per-target ground truth is built exactly as the 2026-11-18 harness built
it for IDA and Binary Ninja; only the tool asked changes. Each target gets
one query, as an agent would ask it ("one_query"). An external class also
gets the by-symbol query the documentation tells callers to add
("with_symbol_query"); for every other target the two are the same.

The binary asked is `$SWIFT_SECTION`, `swift-section` on the `PATH` when it
is unset. Writes `<binary>.swift-section.results.json`.
"""
import bisect
import collections
import json
import os
import struct
import subprocess
import time

WORK = os.environ.get("CROSS_REFERENCE_RECALL_WORK", "/tmp/cross-reference-recall") + "/"
SWIFT_SECTION = os.environ.get("SWIFT_SECTION", "swift-section")
POINTER_SECTIONS = ("__got", "__auth_got", "__objc_superrefs", "__objc_classrefs")


def run_binary(binary_name):
    ground_truth = json.load(open(WORK + binary_name + ".ground-truth.json"))
    references_by_target = {int(key): value for key, value in ground_truth["references"].items()}
    fixups = {int(key): value for key, value in ground_truth["fixups"].items()}
    sections = ground_truth["sections"]
    targets_document = json.load(open(WORK + binary_name + ".targets.json"))
    targets = targets_document["targets"]
    method_list_references = {int(key): value for key, value in targets_document.get("method_list_references", {}).items()}

    text_range = (sections["__text"][0], sections["__text"][0] + sections["__text"][1])

    def is_in_text(address):
        return text_range[0] <= address < text_range[1]

    def section_name(address):
        for name, (start, size) in sections.items():
            if start <= address < start + size:
                return name
        return "?"

    def code_references(target_address):
        return set(instruction for instruction, kind in references_by_target.get(target_address, []) if is_in_text(instruction))

    rebases_by_target = collections.defaultdict(list)
    binds_by_symbol = collections.defaultdict(list)
    for slot_address, (fixup_kind, value) in fixups.items():
        if fixup_kind == "r":
            rebases_by_target[value].append(slot_address)
        else:
            binds_by_symbol[value.split("/")[-1].split()[0]].append(slot_address)

    function_starts_output = subprocess.run(["dyld_info", "-function_starts", WORK + binary_name], capture_output=True, text=True).stdout
    function_starts = sorted(int(line.split()[0], 16) for line in function_starts_output.splitlines()[2:] if line.strip().startswith("0x"))

    def function_end(function_start):
        index = bisect.bisect_right(function_starts, function_start)
        return function_starts[index] if index < len(function_starts) else text_range[1]

    file_bytes = open(WORK + binary_name, "rb").read()

    def read_bytes(address, count):
        offset = address - 0x100000000
        return file_bytes[offset:offset + count]

    def stub_slot(stub_address):
        words = struct.unpack("<III", read_bytes(stub_address, 12))
        immediate = (((words[0] >> 5) & 0x7FFFF) << 2) | ((words[0] >> 29) & 3)
        if immediate & (1 << 20):
            immediate -= 1 << 21
        return (stub_address & ~0xFFF) + (immediate << 12) + ((words[1] >> 10) & 0xFFF)

    # Names the queries need. Finder and ControlCenter keep no local symbols, so
    # class and instance variable names are read from the Objective-C metadata.
    def rebase_target(slot_address):
        fixup = fixups.get(slot_address)
        return fixup[1] if fixup and fixup[0] == "r" else None

    def read_c_string(address):
        if address is None:
            return None
        raw = read_bytes(address, 4096).split(b"\0")[0]
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            return None

    def class_read_only_data(class_address):
        data_pointer = rebase_target(class_address + 32)
        return data_pointer & ~7 if data_pointer is not None else None

    def class_runtime_name(class_address):
        read_only_data = class_read_only_data(class_address)
        return read_c_string(rebase_target(read_only_data + 24)) if read_only_data is not None else None

    def constant_string_characters(constant_string_address):
        flags = struct.unpack("<Q", read_bytes(constant_string_address + 8, 8))[0]
        characters_address = rebase_target(constant_string_address + 16)
        length = struct.unpack("<Q", read_bytes(constant_string_address + 24, 8))[0]
        if characters_address is None:
            return None
        if flags & 0x10:
            return read_bytes(characters_address, length * 2).decode("utf-16-le", "strict")
        try:
            return read_bytes(characters_address, length).decode("utf-8")
        except UnicodeDecodeError:
            return None

    class_list_start, class_list_size = sections["__objc_classlist"]
    listed_classes = [value for slot_address, (fixup_kind, value) in fixups.items() if class_list_start <= slot_address < class_list_start + class_list_size and fixup_kind == "r"]
    instance_variable_names = {}
    for class_address in listed_classes:
        read_only_data = class_read_only_data(class_address)
        if read_only_data is None:
            continue
        instance_variable_list = rebase_target(read_only_data + 48)
        if instance_variable_list is None:
            continue
        entry_size, entry_count = struct.unpack("<II", read_bytes(instance_variable_list, 8))
        owner_name = class_runtime_name(class_address)
        for entry_index in range(entry_count):
            entry_address = instance_variable_list + 8 + entry_index * entry_size
            offset_variable = rebase_target(entry_address)
            if offset_variable is not None:
                instance_variable_names[offset_variable] = (owner_name, read_c_string(rebase_target(entry_address + 8)))

    query_log = []

    def query_references(arguments):
        started = time.monotonic()
        completed = subprocess.run([SWIFT_SECTION, "refs", WORK + binary_name, "--json", *arguments], capture_output=True, text=True)
        elapsed = time.monotonic() - started
        if completed.returncode != 0:
            query_log.append(dict(arguments=arguments, seconds=elapsed, error=completed.stderr.strip()[-400:]))
            return None
        references = json.loads(completed.stdout)["references"]
        query_log.append(dict(arguments=arguments, seconds=elapsed, count=len(references)))
        return references

    def sites(references, keep=lambda reference: True):
        if references is None:
            return None
        return set(int(reference["site"], 16) for reference in references if keep(reference))

    results = []

    def record(category, label, target, ground_truth_code, ground_truth_data, tools, information=None, legitimate=()):
        results.append(dict(
            category=category, label=label, target=target,
            ground_truth_code=sorted(ground_truth_code), ground_truth_data=sorted(ground_truth_data), legitimate=sorted(legitimate),
            tools={key: (sorted(value) if value is not None else None) for key, value in tools.items()},
            information=information,
        ))

    for target in targets.get("A", []):
        stub, selector_reference, selector = target["stub"], target["selector_reference"], target["selector"]
        ground_truth_code = code_references(stub) | code_references(selector_reference)
        found = sites(query_references(["--selector=" + selector]))
        record("A", selector, stub, ground_truth_code, set(), {"one_query": found, "with_symbol_query": found})

    for target in targets.get("B", []):
        if target["kind"] == "ext":
            symbol = target["symbol"].split("/")[-1]
            all_slots = binds_by_symbol[symbol]
            pointer_slots = [slot for slot in all_slots if section_name(slot) in POINTER_SECTIONS]
            ground_truth_code = set().union(*[code_references(slot) for slot in pointer_slots])
            class_name = symbol.split("_OBJC_CLASS_$_", 1)[1]
            by_class = sites(query_references(["--class=" + class_name]))
            by_symbol = sites(query_references(["--symbol=" + symbol]))
            both = None if by_class is None and by_symbol is None else (by_class or set()) | (by_symbol or set())
            record("B", symbol, None, ground_truth_code, set(all_slots), {"one_query": by_class, "with_symbol_query": both}, {"class": class_name})
        else:
            class_address = target["class_address"]
            slots = [slot for slot in rebases_by_target.get(class_address, []) if section_name(slot) in POINTER_SECTIONS]
            ground_truth_code = code_references(class_address)
            for slot in slots:
                ground_truth_code |= code_references(slot)
            class_name = class_runtime_name(class_address)
            found = sites(query_references(["--class=" + class_name])) if class_name else None
            record("B", "own@" + hex(class_address), class_address, ground_truth_code, set(rebases_by_target.get(class_address, [])), {"one_query": found, "with_symbol_query": found}, {"class": class_name})

    for stub in targets.get("C", []):
        ground_truth_code = code_references(stub)
        slot = stub_slot(stub)
        fixup = fixups.get(slot)
        symbol = fixup[1].split("/")[-1].split()[0] if fixup else None
        ground_truth_code |= code_references(slot)
        found = sites(query_references(["--symbol=" + symbol])) if symbol else None
        record("C", symbol, stub, ground_truth_code, {slot}, {"one_query": found, "with_symbol_query": found})

    for function_start in targets.get("D", []):
        end = function_end(function_start)
        ground_truth_code = {instruction for instruction, kind in references_by_target.get(function_start, []) if is_in_text(instruction) and not (function_start <= instruction < end)}
        found = sites(query_references(["--function=" + hex(function_start)]))
        record("D", hex(function_start), function_start, ground_truth_code, set(rebases_by_target.get(function_start, [])), {"one_query": found, "with_symbol_query": found})

    for target in targets.get("E", []):
        address = target["address"]
        ground_truth_code = code_references(address)
        legitimate = set()
        for constant_string in [slot - 16 for slot in rebases_by_target.get(address, []) if section_name(slot) == "__cfstring"]:
            legitimate |= code_references(constant_string)
        if target["kind"] == "cstr":
            characters, wanted_key = read_c_string(address), "cString"
        else:
            characters, wanted_key = constant_string_characters(address), "constantString"
        references = query_references(["--string=" + characters]) if characters else None
        found = sites(references, lambda reference: wanted_key in reference["target"])
        record("E", target["kind"] + "@" + hex(address), address, ground_truth_code, set(rebases_by_target.get(address, [])), {"one_query": found, "with_symbol_query": found}, {"characters": characters, "all_matches": len(references or [])}, legitimate)

    for address in targets.get("F", []):
        ground_truth_code = code_references(address)
        owner_name, instance_variable_name = instance_variable_names.get(address, (None, None))
        found = sites(query_references(["--ivar=%s.%s" % (owner_name, instance_variable_name)])) if instance_variable_name else None
        record("F", hex(address), address, ground_truth_code, set(rebases_by_target.get(address, [])), {"one_query": found, "with_symbol_query": found}, {"ivar": "%s.%s" % (owner_name, instance_variable_name)})

    for target in targets.get("H", []) + targets.get("G", []):
        function_start = target["function"]
        end = function_end(function_start)
        ground_truth_data = set(method_list_references.get(function_start, [])) | set(rebases_by_target.get(function_start, []))
        ground_truth_code = {instruction for instruction, kind in references_by_target.get(function_start, []) if is_in_text(instruction) and not (function_start <= instruction < end)}
        found = sites(query_references(["--function=" + hex(function_start)]))
        record(target.get("category", "H"), target["kind"] + "@" + hex(function_start), function_start, ground_truth_code, ground_truth_data, {"one_query": found, "with_symbol_query": found})

    json.dump(dict(results=results, queries=query_log), open(WORK + binary_name + ".swift-section.results.json", "w"))
    errors = [entry for entry in query_log if "error" in entry]
    seconds = [entry["seconds"] for entry in query_log]
    print(binary_name, "targets", len(results), "queries", len(query_log), "errors", len(errors),
          "seconds total %.1f median %.2f max %.2f" % (sum(seconds), sorted(seconds)[len(seconds) // 2], max(seconds)))
    for entry in errors:
        print("  error", entry["arguments"], entry["error"])


version = subprocess.run([SWIFT_SECTION, "--version"], capture_output=True, text=True).stdout.strip()
print("swift-section", version, "at", SWIFT_SECTION)
run_binary("Finder")
run_binary("ControlCenter")
