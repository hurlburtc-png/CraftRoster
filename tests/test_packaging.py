"""Ensure the download extracts directly into an AddOns directory."""
import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]


class PackageTests(unittest.TestCase):
    def test_archive_has_only_one_addon_folder_and_all_modules(self):
        spec = importlib.util.spec_from_file_location('package_addon', ROOT / 'scripts/package_addon.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with TemporaryDirectory() as temporary:
            destination = module.package(Path(temporary) / 'CraftRoster.zip')
            with ZipFile(destination) as archive:
                self.assertIsNone(archive.testzip())
                names = archive.namelist()
                self.assertEqual({name.split('/')[0] for name in names}, {'CraftRoster'})
                self.assertIn('CraftRoster/CraftRoster.toc', names)
                for line in (ROOT / 'CraftRoster/CraftRoster.toc').read_text().splitlines():
                    if line.strip() and not line.startswith('#'):
                        self.assertIn('CraftRoster/' + line.strip(), names)
                addons = Path(temporary) / 'AddOns'
                archive.extractall(addons)
                self.assertTrue((addons / 'CraftRoster/CraftRoster.toc').is_file())
                self.assertEqual((addons / 'CraftRoster/Directory.lua').read_bytes(),
                                 (ROOT / 'CraftRoster/Directory.lua').read_bytes())
