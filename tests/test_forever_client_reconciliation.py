import tempfile
import unittest
from pathlib import Path
from scripts.reconcile_forever_client import records, reconcile

class ForeverClientReconciliationTests(unittest.TestCase):
    def test_exact_ids_and_output_conflicts(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "Alchemy.lua").write_text(
                '-- build 1.60.1.69977\n'
                'lib:LoadCore(171, {\n'
                ' [2329] = {\n ["craftedItemId"] = 2454,\n ["reagents"] = { [765] = 1 },\n },\n'
                ' [2331] = {\n ["craftedItemId"] = 2455,\n },\n'
                '})\n', encoding="utf-8")
            index, builds = records(Path(tmp))
            self.assertEqual(set(index), {2329, 2331})
            self.assertEqual(builds["Alchemy.lua"], "1.60.1.69977")
            rows = reconcile({"recipes": [
                {"spellID":2329,"profession":"Alchemy","name":"A","output":2454},
                {"spellID":2331,"profession":"Alchemy","name":"B","output":9999},
                {"spellID":9999,"profession":"Alchemy","name":"C","output":1}]}, index)
            self.assertEqual([x["status"] for x in rows],
                             ["exact_forever_spell_and_output_match","output_conflict","missing_exact_forever_spell"])
            self.assertTrue(all(not x["acquisitionVerified"] for x in rows))

    def test_duplicate_spell_disambiguation_and_missing_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            for filename, output in (("Cooking.lua", 100), ("Fishing.lua", 200)):
                Path(tmp, filename).write_text(
                    '-- build 1.60.1.69977\n'
                    'lib:LoadCore(185, {\n'
                    ' [2543] = {\n'
                    ' ["craftedItemId"] = %d,\n'
                    ' },\n'
                    '})\n' % output, encoding="utf-8")
            index, _ = records(Path(tmp))
            self.assertEqual(len(index[2543]), 2)
            rows = reconcile({"recipes": [
                {"spellID":2543,"profession":"Cooking","name":"Matched","output":100},
                {"spellID":2543,"profession":"Cooking","name":"Ambiguous","output":300},
                {"spellID":2543,"profession":"Cooking","name":"Unknown output","output":None}
            ]}, index)
            self.assertEqual([r["status"] for r in rows], [
                "exact_forever_spell_and_output_match",
                "ambiguous_forever_spell",
                "exact_forever_spell_output_unchecked"
            ])
            self.assertEqual(rows[0]["candidateCount"], 2)

if __name__ == "__main__":
    unittest.main()
