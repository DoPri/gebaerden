#!/usr/bin/env python3
"""Reports line coverage from coverage/lcov.info and fails below a threshold.

lcov only lists files a test actually loaded. Everything under lib/ counts,
generated code and files opting out with a coverage:ignore-file header do not.
"""

import collections
import os
import sys

THRESHOLD = float(sys.argv[1]) if len(sys.argv) > 1 else 99.0
REPORT = "coverage/lcov.info"


def measured():
    hits = collections.OrderedDict()
    current = None
    with open(REPORT) as report:
        for line in report:
            line = line.strip()
            if line.startswith("SF:"):
                current = line[3:]
                hits.setdefault(current, {})
            elif line.startswith("DA:"):
                number, count = line[3:].split(",")[:2]
                number = int(number)
                hits[current][number] = hits[current].get(number, 0) + int(count)
    return hits


def wanted():
    for root, _, files in os.walk("lib"):
        for name in sorted(files):
            if not name.endswith(".dart") or name.endswith(".g.dart"):
                continue
            path = os.path.join(root, name)
            with open(path) as source:
                if source.readline().startswith("// coverage:ignore-file"):
                    continue
            yield path


def main():
    if not os.path.exists(REPORT):
        sys.exit(f"{REPORT} is missing, run flutter test --coverage first")

    hits = measured()
    total = covered = 0
    gaps = []

    for path in wanted():
        lines = hits.get(path, {})
        counted = len(lines)
        hit = sum(1 for count in lines.values() if count > 0)
        total += counted
        covered += hit
        if hit < counted:
            gaps.append((counted - hit, hit, counted, path))

    for missing, hit, counted, path in sorted(gaps, reverse=True):
        print(f"{hit / counted * 100:6.1f}%  {hit:5}/{counted:<5}  {path}")

    percent = covered / total * 100 if total else 0.0
    print(f"\n{covered}/{total} lines, {percent:.2f} percent")

    if percent < THRESHOLD:
        sys.exit(f"below {THRESHOLD:.2f} percent")


if __name__ == "__main__":
    main()
