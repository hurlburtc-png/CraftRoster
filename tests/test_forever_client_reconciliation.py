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

if __name__ == "__main__":
    unittest.main()
