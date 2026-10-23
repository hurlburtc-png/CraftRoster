#!/usr/bin/env python3
"""Generate an honest, complete Forever recipe verification queue.

Classic acquisition coverage is not proof of Forever acquisition.
Optional evidence JSON: {"recipes":[{"spellID":123,"output":456,
"craftEvidence":"URL","acquisitionEvidence":"URL","materialsEvidence":"URL",
"status":"verified_forever","notes":"..."}]}.
"""
import argparse
import csv
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ("spellID", "profession", "name", "output", "teachingItem",
          "hidden", "classicStatus", "classicSources", "foreverCraft",
          "foreverMaterials", "foreverAcquisition", "craftEvidence",
          "materialsEvidence", "acquisitionEvidence", "notes")
VALID = {"verified_forever", "unknown", "conflicting", "unobtainable"}

def make_report(coverage, evidence=None):
    recipes = coverage["recipes"]
    if len(recipes) != coverage["summary"]["catalogue"]:
        raise ValueError("Catalogue total does not match recipe rows")
    evidence = evidence or {"recipes": []}
    indexed = {}
    for item in evidence.get("recipes", []):
        key = int(item["spellID"])
        if key in indexed:
            raise ValueError("Duplicate evidence spellID: %s" % key)
        indexed[key] = item
    known = {int(r["spellID"]) for r in recipes}
    if len(known) != len(recipes):
        raise ValueError("Duplicate catalogue spellID")
    if set(indexed) - known:
        raise ValueError("Evidence references unknown spell IDs")
    rows = []
    for r in sorted(recipes, key=lambda x: (x["profession"], x["name"], x["spellID"])):
        ev = indexed.get(int(r["spellID"]), {})
        statuses = {}
        for category, url_key in (("Craft", "craftEvidence"),
                                  ("Materials", "materialsEvidence"),
                                  ("Acquisition", "acquisitionEvidence")):
            status = ev.get(category.lower() + "Status", "unknown")
            if status not in VALID:
                raise ValueError("Invalid verification status")
            if status == "verified_forever" and not ev.get(url_key):
                raise ValueError("Forever verified status requires evidence URL: %s" % r["spellID"])
            statuses[category] = status
        rows.append(dict(spellID=r["spellID"], profession=r["profession"],
                         name=r["name"], output=r.get("output"),
                         teachingItem=r.get("item"), hidden=r.get("hidden", False),
                         classicStatus=r["status"], classicSources=r["sources"],
                         foreverCraft=statuses["Craft"],
                         foreverMaterials=statuses["Materials"],
                         foreverAcquisition=statuses["Acquisition"],
                         craftEvidence=ev.get("craftEvidence", ""),
                         materialsEvidence=ev.get("materialsEvidence", ""),
                         acquisitionEvidence=ev.get("acquisitionEvidence", ""),
                         notes=ev.get("notes", "")))
    totals = {field: dict(Counter(r[field] for r in rows))
              for field in ("classicStatus", "foreverCraft",
                            "foreverMaterials", "foreverAcquisition")}
    return rows, {"catalogue": len(rows), "statusTotals": totals,
                  "byProfession": dict(sorted(Counter(r["profession"] for r in rows).items()))}

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--coverage", type=Path, default=ROOT / "data/classic-source-coverage.json")
    p.add_argument("--evidence", type=Path)
    p.add_argument("--out", type=Path, default=ROOT / "build/forever-verification")
    args = p.parse_args()
    coverage = json.loads(args.coverage.read_text(encoding="utf-8"))
    evidence = json.loads(args.evidence.read_text(encoding="utf-8")) if args.evidence else None
    rows, summary = make_report(coverage, evidence)
    args.out.mkdir(parents=True, exist_ok=True)
    with (args.out / "recipes.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))

if __name__ == "__main__":
    main()
