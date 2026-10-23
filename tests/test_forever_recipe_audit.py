import unittest
from scripts.audit_forever_recipes import make_report

class ForeverRecipeAuditTests(unittest.TestCase):
    def setUp(self):
        self.coverage = {"summary": {"catalogue": 2}, "recipes": [
            {"spellID": 1, "profession": "Alchemy", "name": "A", "output": 3,
             "item": None, "hidden": False, "status": "covered", "sources": 1},
            {"spellID": 2, "profession": "Tailoring", "name": "B", "output": 4,
             "item": 9, "hidden": False, "status": "no_exact_classic_spell", "sources": 0},
        ]}

    def test_every_recipe_accounted_for_without_false_verification(self):
        rows, summary = make_report(self.coverage)
        self.assertEqual(len(rows), 2)
        self.assertEqual(summary["statusTotals"]["foreverAcquisition"]["unknown"], 2)
        self.assertEqual(rows[0]["classicStatus"], "covered")
        self.assertEqual(rows[0]["foreverAcquisition"], "unknown")

    def test_verification_requires_evidence(self):
        with self.assertRaises(ValueError):
            make_report(self.coverage, {"recipes": [{"spellID": 1,
                "acquisitionStatus": "verified_forever"}]})

    def test_evidence_for_unknown_recipe_rejected(self):
        with self.assertRaises(ValueError):
            make_report(self.coverage, {"recipes": [{"spellID": 99}]})

    def test_duplicate_evidence_rejected(self):
        with self.assertRaises(ValueError):
            make_report(self.coverage, {"recipes": [{"spellID": 1}, {"spellID": 1}]})

    def test_evidence_url_enables_verification(self):
        rows, _ = make_report(self.coverage, {"recipes": [{"spellID": 1,
            "craftStatus": "verified_forever", "craftEvidence": "https://example.org/1"}]})
        self.assertEqual(rows[0]["foreverCraft"], "verified_forever")
        self.assertEqual(rows[0]["foreverAcquisition"], "unknown")

if __name__ == "__main__":
    unittest.main()
