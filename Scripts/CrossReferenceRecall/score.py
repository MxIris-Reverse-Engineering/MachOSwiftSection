"""Scores swift-section's answers with the 2026-11-18 scoring rules, puts
them next to that run's IDA rows (ida-2026-11-18.txt), and lists every miss
and extra with its disassembly line in `swift-section.details.txt`.

A reference found counts when the tool's instruction is the ground truth's,
the `adrp` it pairs with, or up to 16 bytes after it; a hit inside the
target function itself, a data reference, or a reference through a
constant string to its characters is set aside rather than counted extra.
"""
import bisect
import collections
import json
import os
import re
import subprocess

WORK = os.environ.get("CROSS_REFERENCE_RECALL_WORK", "/tmp/cross-reference-recall") + "/"
IDA_ROWS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ida-2026-11-18.txt")
TOOLS = ("one_query", "with_symbol_query")

summary = {}
details = []
for binary_name in ("Finder", "ControlCenter"):
    results = json.load(open(WORK + binary_name + ".swift-section.results.json"))["results"]
    ground_truth = json.load(open(WORK + binary_name + ".ground-truth.json"))
    sections = ground_truth["sections"]
    pairs = {int(key): value for key, value in json.load(open(WORK + binary_name + ".pairs.json")).items()}
    mnemonics = {}
    lines = {}
    for line in open(WORK + binary_name + ".otool"):
        parts = line.split("\t")
        if len(parts) > 1 and len(parts[0]) == 16:
            address = int(parts[0], 16)
            mnemonics[address] = parts[1]
            lines[address] = line.rstrip("\n")
    text_range = (sections["__text"][0], sections["__text"][0] + sections["__text"][1])

    def is_in_text(address):
        return text_range[0] <= address < text_range[1]

    def section_name(address):
        for name, (start, size) in sections.items():
            if start <= address < start + size:
                return name
        return "?"

    function_starts_output = subprocess.run(["dyld_info", "-function_starts", WORK + binary_name], capture_output=True, text=True).stdout
    function_starts = sorted(int(line.split()[0], 16) for line in function_starts_output.splitlines()[2:] if line.strip().startswith("0x"))

    def function_end(function_start):
        index = bisect.bisect_right(function_starts, function_start)
        return function_starts[index] if index < len(function_starts) else text_range[1]

    counters = collections.defaultdict(collections.Counter)
    extra_kinds = collections.defaultdict(collections.Counter)
    for result in results:
        category = result["category"] + ("-" + result["label"].split("@")[0] if result["category"] == "G" else "")
        target = result["target"]
        ground_truth_code = set(result["ground_truth_code"])
        ground_truth_data = set(result["ground_truth_data"])
        legitimate = set(result["legitimate"])
        if category in ("C", "D"):
            ground_truth_data = set()
        legitimate_addresses = set()
        for address in legitimate:
            legitimate_addresses.update({address, pairs.get(address, -1)})
        low, high = (target, function_end(target)) if (target and is_in_text(target)) else (0, 0)
        for tool in TOOLS:
            counter = counters[(category, tool)]
            counter["targets"] += 1
            answer = set(result["tools"][tool] or [])
            found = set()
            data_found = set()
            for site in sorted(answer):
                hits = [expected for expected in ground_truth_code if site == expected or site == pairs.get(expected) or (is_in_text(site) and 0 < site - expected <= 16)]
                if hits:
                    found |= set(hits)
                    counter["matched"] += 1
                    continue
                if low <= site < high:
                    counter["inside_target"] += 1
                    continue
                matched_data = [expected for expected in ground_truth_data if not is_in_text(site) and 0 <= expected - site < 32]
                if matched_data:
                    data_found |= set(matched_data)
                    continue
                if site in legitimate_addresses:
                    counter["through_constant_string"] += 1
                    continue
                kind = "text:" + mnemonics.get(site, "?") if is_in_text(site) else section_name(site)
                extra_kinds[(category, tool)][kind] += 1
                counter["extra"] += 1
                if tool == "with_symbol_query":
                    details.append(("EXTRA", binary_name, category, result["label"], hex(site), lines.get(site, kind)))
            counter["ground_truth_code"] += len(ground_truth_code)
            counter["found"] += len(found)
            counter["ground_truth_data"] += len(ground_truth_data)
            counter["data_found"] += len(data_found)
            if tool == "with_symbol_query":
                for missed in sorted(ground_truth_code - found):
                    details.append(("MISS", binary_name, category, result["label"], hex(missed), lines.get(missed, "?")))
    summary[binary_name] = {"%s|%s" % key: counter for key, counter in counters.items()}

# The 2026-11-18 IDA rows, e.g. "Finder A ida1 code 20/22 data 0/0 extra 0 ..."
ida_rows = {}
for line in open(IDA_ROWS):
    match = re.match(r"(\w+) (\S+) (ida1|ida2) code (\d+)/(\d+) data (\d+)/(\d+) extra (\d+)", line)
    if match:
        binary_name, category, tool, found, total, data_found, data_total, extra = match.groups()
        ida_rows[(binary_name, category, "one_query" if tool == "ida1" else "two_hops")] = tuple(int(value) for value in (found, total, data_found, data_total, extra))

print("binary         category        GT  IDA-1  IDA-2  ours-1  ours-2 | data GT  IDA  ours | extras IDA-2  ours-2")
totals = collections.Counter()
for binary_name in ("Finder", "ControlCenter"):
    for category in sorted({key.split("|")[0] for key in summary[binary_name]}):
        one_query = summary[binary_name][category + "|one_query"]
        with_symbol_query = summary[binary_name][category + "|with_symbol_query"]
        ida_one_query = ida_rows.get((binary_name, category, "one_query"))
        ida_two_hops = ida_rows.get((binary_name, category, "two_hops"))
        if ida_one_query and ida_one_query[1] != one_query["ground_truth_code"]:
            print("  GROUND TRUTH DIFFERS from 2026-11-18:", binary_name, category, ida_one_query[1], one_query["ground_truth_code"])
        print("%-14s %-14s %4d  %5s  %5s  %6d  %6d | %7d  %3s  %4d | %12s  %6d" % (
            binary_name, category, one_query["ground_truth_code"],
            ida_one_query[0] if ida_one_query else "-", ida_two_hops[0] if ida_two_hops else "-",
            one_query["found"], with_symbol_query["found"],
            one_query["ground_truth_data"], ida_two_hops[2] if ida_two_hops else "-", with_symbol_query["data_found"],
            ida_two_hops[4] if ida_two_hops else "-", with_symbol_query["extra"]))
        totals["ground_truth"] += one_query["ground_truth_code"]
        totals["one_query"] += one_query["found"]
        totals["with_symbol_query"] += with_symbol_query["found"]
        totals["ida_one_query"] += ida_one_query[0] if ida_one_query else 0
        totals["ida_two_hops"] += ida_two_hops[0] if ida_two_hops else 0
print()
print("code references %d: IDA one query %.1f%%, two hops %.1f%%; swift-section one query %.1f%%, with the by-symbol query %.1f%%" % (
    totals["ground_truth"], 100 * totals["ida_one_query"] / totals["ground_truth"], 100 * totals["ida_two_hops"] / totals["ground_truth"],
    100 * totals["one_query"] / totals["ground_truth"], 100 * totals["with_symbol_query"] / totals["ground_truth"]))

with open(WORK + "swift-section.details.txt", "w") as details_file:
    for entry in details:
        details_file.write("\t".join(str(field) for field in entry) + "\n")
print("misses", sum(1 for entry in details if entry[0] == "MISS"), "extras", sum(1 for entry in details if entry[0] == "EXTRA"), "->", WORK + "swift-section.details.txt")
