#!/usr/bin/env python3
"""Reconcile every CraftRoster recipe with the bundled Forever client recipe tables.

Exact spell IDs only. This checks identity/output, NOT acquisition or server loot.
"""
import argparse
import csv
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "vendor/ProfessionDB/Data/Forever/_core"
RECIPE = re.compile(r'^\s*\[(\d+)\] = \{\s*$', re.M)
CRAFTED = re.compile(r'\["craftedItemId"\] = (\d+)')
BUILD = re.compile(r'-- build ([\d.]+)')

def records(folder):
    index = {}
    builds = {}
    for path in sorted(folder.glob("*.lua")):
        text = path.read_text(encoding="utf-8")
        match = BUILD.search(text)
        builds[path.name] = match.group(1) if match else "unknown"
        positions = list(RECIPE.finditer(text))
        for i, found in enumerate(positions):
            spell = int(found.group(1))
            # The first top-level closing brace before the next recipe entry
            # is enough for the craftedItemId field; avoid nested reagent IDs.
            next_start = positions[i+1].start() if i+1 < len(positions) else len(text)
            body = text[found.end():next_start]
            crafted = CRAFTED.search(body)
            record = {"output": int(crafted.group(1)) if crafted else None,
                      "sourceFile": path.name, "sourceBuild": builds[path.name]}
            index.setdefault(spell, []).append(record)
    return index, builds

def reconcile(coverage, index):
    result = []
    for entry in coverage["recipes"]:
        spell = int(entry["spellID"])
        candidates = index.get(spell, [])
        # Duplicate IDs are retained rather than silently overwriting evidence.
        # A matching output disambiguates a shared spell ID where possible.
        matches = [v for v in candidates if entry.get("output") and v["output"] == int(entry["output"])]
        # A spell can appear in multiple bundled tables; profession is independent evidence.
        # Only narrow when the source filename unambiguously identifies the profession.
        profession = re.sub(r"[^a-z0-9]", "", str(entry["profession"]).lower())
        pool = matches if matches else candidates
        profession_matches = [v for v in pool if re.sub(r"[^a-z0-9]", "", Path(v["sourceFile"]).stem.lower()) == profession]
        if len(profession_matches) == 1:
            found = profession_matches[0]
        elif len(pool) == 1:
            found = pool[0]
        else:
            found = None
        if len(pool) > 1 and not found:
            status = "ambiguous_forever_spell"
        elif not found:
            status = "missing_exact_forever_spell"
        elif entry.get("output") and found["output"] and int(entry["output"]) != found["output"]:
            status = "output_conflict"
        elif entry.get("output") and not found["output"]:
            status = "missing_forever_output"
        elif not entry.get("output"):
            status = "exact_forever_spell_output_unchecked"
        else:
            status = "exact_forever_spell_and_output_match"
        result.append({"spellID": spell, "profession": entry["profession"],
                       "name": entry["name"], "catalogueOutput": entry.get("output"),
                       "foreverOutput": found["output"] if found else None,
                       "sourceFile": found["sourceFile"] if found else None,
                       "sourceBuild": found["sourceBuild"] if found else None,
                       "candidateCount": len(candidates), "status": status, "acquisitionVerified": False,
                       "reviewAction": ("Confirm catalogue crafted-item ID against the Forever client output" if status == "exact_forever_spell_output_unchecked" else
                                        "Investigate conflicting crafted-item IDs" if status == "output_conflict" else
                                        "Disambiguate spell ID using profession and client evidence" if status == "ambiguous_forever_spell" else
                                        "Find matching Forever client spell and crafted output"),
                       "suggestedOutput": found["output"] if found and not entry.get("output") else None})
    return result

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--coverage", type=Path, default=ROOT / "data/classic-source-coverage.json")
    p.add_argument("--core", type=Path, default=CORE)
    p.add_argument("--out", type=Path, default=ROOT / "build/forever-client-reconciliation.json")
    p.add_argument("--review-out", type=Path, default=ROOT / "build/forever-recipe-review.csv")
    args = p.parse_args()
    coverage = json.loads(args.coverage.read_text(encoding="utf-8"))
    index, builds = records(args.core)
    result = reconcile(coverage, index)
    if len(result) != coverage["summary"]["catalogue"]:
        raise ValueError("Catalogue rows missing")
    matched = sum(row["status"] == "exact_forever_spell_and_output_match" for row in result)
    print(f"PROGRESS: {len(result)}/{len(result)} ({100.0 if result else 0.0:.1f}%) entries processed", flush=True)
    print(f"CLIENT ID/OUTPUT MATCH: {matched}/{len(result)} ({100*matched/len(result) if result else 0:.1f}%)", flush=True)
    print("FULLY FOREVER VERIFIED: 0 (acquisition/material verification not performed by this script)", flush=True)
    report = {"total": len(result), "processed": len(result), "processedPercent": 100.0 if result else 0.0,
              "clientMatched": matched, "clientMatchedPercent": round(100*matched/len(result),2) if result else 0,
              "fullyVerified": 0, "foreverCoreSpells": len(index),
              "builds": builds, "statuses": dict(Counter(r["status"] for r in result)),
              "note": "Exact-ID client craft comparison only; not proof of acquisition, reagents or Forever server availability.",
              "recipes": result}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    unresolved = [row for row in result if row["status"] != "exact_forever_spell_and_output_match"]
    args.review_out.parent.mkdir(parents=True, exist_ok=True)
    with args.review_out.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["spellID", "profession", "name", "catalogueOutput", "foreverOutput", "sourceFile", "sourceBuild", "candidateCount", "status", "acquisitionVerified", "reviewAction", "suggestedOutput"])
        writer.writeheader()
        writer.writerows(unresolved)
    print(f"REVIEW QUEUE: {len(unresolved)} entries written to {args.review_out}", flush=True)
    print(json.dumps({k:v for k,v in report.items() if k != "recipes"}, indent=2))

if __name__ == "__main__":
    main()
