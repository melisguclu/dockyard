#!/usr/bin/env python3

import statistics
import sys
import xml.etree.ElementTree as ET

SUBSYSTEM = "com.dockyard.app"
INTERVALS = ("panel-layout", "snapshot-build", "preference-read", "icon-rasterize", "stack-read")


def rows(path):
    node = ET.parse(path).getroot().find("node")
    columns = [column.find("mnemonic").text for column in node.find("schema").findall("col")]
    seen = {}
    for row in node.iter("row"):
        record = {}
        for index, cell in enumerate(row):
            key = columns[index] if index < len(columns) else cell.tag
            if "ref" in cell.attrib:
                record[key] = seen.get(cell.attrib["ref"])
                continue
            value = cell.get("fmt")
            if cell.tag in ("start-time", "duration"):
                value = int(cell.text) if cell.text else None
            if "id" in cell.attrib:
                seen[cell.attrib["id"]] = value
            record[key] = value
        yield record


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * fraction))]


def report(name, selected):
    if not selected:
        return
    durations = [row["duration"] / 1e6 for row in selected]
    if len(selected) == 1:
        print(f"{name}: 1 interval, {durations[0]:.2f} ms")
        return

    starts = sorted(row["start"] for row in selected)
    span = (starts[-1] - starts[0]) / 1e9
    gaps = [(b - a) / 1e6 for a, b in zip(starts, starts[1:])]

    print(f"{name}: {len(selected)} intervals over {span:.2f} s, {len(selected) / span:.1f} per second")
    print(
        f"  duration   p50 {statistics.median(durations):.3f} ms"
        f"   p95 {percentile(durations, 0.95):.3f}"
        f"   p99 {percentile(durations, 0.99):.3f}"
        f"   worst {max(durations):.3f}"
    )
    print(
        f"  interval   p50 {statistics.median(gaps):.2f} ms"
        f"   p95 {percentile(gaps, 0.95):.2f}"
        f"   p99 {percentile(gaps, 0.99):.2f}"
        f"   worst {max(gaps):.2f}"
    )

    if name != "panel-layout":
        return

    refresh = statistics.median(gaps)
    late = [gap for gap in gaps if gap > refresh * 1.5]
    missed = sum(round(gap / refresh) - 1 for gap in late)
    print(
        f"  pacing     {len(late)} intervals over 1.5 refresh periods"
        f"   {missed} missed vsyncs   {missed / (span * (1000 / refresh)) * 100:.2f}% of the display's frames"
    )


def main():
    everything = [row for row in rows(sys.argv[1]) if row.get("subsystem") == SUBSYSTEM]
    for name in INTERVALS:
        report(name, [row for row in everything if row.get("name") == name])


if __name__ == "__main__":
    main()
