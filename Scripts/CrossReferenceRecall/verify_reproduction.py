"""Checks that ground_truth.py reproduced the 2026-11-18 run: the totals and
target lists below are copied from that run's printed output. Exits with 1
when anything differs — the numbers would no longer compare with the IDA
baseline in ida-2026-11-18.txt."""
import json
import os
import sys

WORK = os.environ.get("CROSS_REFERENCE_RECALL_WORK", "/tmp/cross-reference-recall") + "/"

expected_reference_totals = {"Finder": 511138, "ControlCenter": 359773}
expected_stub_counts = {"Finder": 8809, "ControlCenter": 1363}
expected_targets = {
    "Finder": {
        "C": [4303335148, 4303340684, 4303335740, 4303349948, 4303345276, 4303334844, 4303359708, 4303350588],
        "D": [4296493604, 4297114024, 4302277612, 4302218044, 4301417104, 4295793096, 4301308772, 4301449572],
        "F": [4307227568, 4307236272, 4307226952, 4307236864, 4307231160, 4307236592, 4307228448, 4307226664],
        "first selectors": ["propertiesToUpdate", "fiDomain"],
    },
    "ControlCenter": {
        "C": [4301922220, 4301907948, 4301911132, 4301927564, 4301924412, 4301927388, 4301895132, 4301924860],
        "D": [4295169504, 4301400024, 4295515008, 4295483488, 4295324396, 4296870092, 4297616600, 4295299536],
        "F": [],
        "first selectors": ["sfSymbolNameCase", "ssidData"],
    },
}

failures = []
for binary_name, expectation in expected_targets.items():
    ground_truth = json.load(open(WORK + binary_name + ".ground-truth.json"))
    reference_total = sum(len(entries) for entries in ground_truth["references"].values())
    stub_count = len(ground_truth["stubs"])
    print(binary_name, "references", reference_total, "expected", expected_reference_totals[binary_name], "stubs", stub_count, "expected", expected_stub_counts[binary_name])
    if reference_total != expected_reference_totals[binary_name] or stub_count != expected_stub_counts[binary_name]:
        failures.append(binary_name + " ground truth totals")
    targets = json.load(open(WORK + binary_name + ".targets.json"))["targets"]
    for category in ("C", "D", "F"):
        matches = targets.get(category, []) == expectation[category]
        print(binary_name, category, "matches" if matches else "DIFFERS")
        if not matches:
            failures.append(binary_name + " " + category)
    first_selectors = [target["selector"] for target in targets["A"][:2]]
    matches = first_selectors == expectation["first selectors"]
    print(binary_name, "A", first_selectors, "matches" if matches else "DIFFERS")
    if not matches:
        failures.append(binary_name + " A")
    print(binary_name, {category: len(entries) for category, entries in targets.items()})

if failures:
    print("NOT REPRODUCED:", failures)
    sys.exit(1)
print("reproduced")
