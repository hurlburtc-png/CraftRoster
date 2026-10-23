"""Fast release preflight; run with python -m unittest discover -s tests."""
import pathlib
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

class ReleaseGate(unittest.TestCase):
    def test_toc_load_order(self):
        toc = (ROOT / "CraftRoster.toc").read_text(encoding="utf-8")
        files = [s.strip().replace("\\", "/") for s in toc.splitlines()
                 if s.strip() and not s.lstrip().startswith("#")]
        self.assertEqual(len(files), len(set(files)), "Duplicate TOC entry")
        for file in files:
            self.assertTrue((ROOT / file).is_file(), "Missing TOC file: " + file)
        self.assertLess(files.index("ClassicSourceData.lua"), files.index("ClassicSources.lua"))
        self.assertLess(files.index("ClassicSources.lua"), files.index("RecipeSources.lua"))

    def test_instance_sources_never_print_coordinates(self):
        src = (ROOT / "ClassicSources.lua").read_text(encoding="utf-8")
        self.assertIn('local skipCoords=instanced or source.kind=="boss"', src)
        self.assertIn('if not skipCoords and percent(source.x)', src)
        self.assertIn('function Classic:IsInstanced(source)', src)

    def test_zip_layout_if_release_present(self):
        archives = list(ROOT.glob("*beta*.zip"))
        for archive in archives:
            with self.subTest(archive=archive.name), zipfile.ZipFile(archive) as z:
                names = [n for n in z.namelist() if not n.endswith("/")]
                self.assertIn("CraftRoster/CraftRoster.toc", names)
                self.assertTrue(all(n.startswith("CraftRoster/") for n in names),
                                "ZIP contains unexpected outer folder")
                self.assertFalse(any(n.startswith("CraftRoster/CraftRoster/") for n in names))

if __name__ == "__main__":
    unittest.main()
