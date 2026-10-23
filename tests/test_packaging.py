"""Ensure the download extracts directly into an AddOns directory."""
import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]


class PackageTests(unittest.TestCase):
    def test_checked_in_download_is_valid_single_folder_release(self):
        with ZipFile(ROOT / 'CraftRoster.zip') as archive:
            self.assertIsNone(archive.testzip())
            files = ['CraftRoster.toc'] + [line.strip() for line in
                     archive.read('CraftRoster/CraftRoster.toc').decode('utf-8').splitlines()
                     if line.strip() and not line.startswith('#')]
            files += ['vendor/ProfessionDB/LICENSE', 'vendor/ProfessionDB/manifest.json']
            files += [name[len('CraftRoster/'):] for name in archive.namelist() if name.startswith('CraftRoster/vendor/ClassicSources/') and name.endswith('.md')]
            self.assertEqual(set(archive.namelist()), {'CraftRoster/'} | {'CraftRoster/' + name for name in files})
            # The checked-in ZIP is a manually published release and may lag
            # development sources. Fresh packages are checked byte-for-byte below.

    def test_package_has_stable_metadata_and_repeatable_bytes(self):
        spec = importlib.util.spec_from_file_location('package_addon', ROOT / 'scripts/package_addon.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with TemporaryDirectory() as temporary:
            first = module.package(Path(temporary) / 'first.zip')
            second = module.package(Path(temporary) / 'second.zip')
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with ZipFile(first) as archive:
                self.assertTrue(all(info.date_time == (1980, 1, 1, 0, 0, 0) for info in archive.infolist()))

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
                for line in (ROOT / 'CraftRoster.toc').read_text().splitlines():
                    if line.strip() and not line.startswith('#'):
                        self.assertIn('CraftRoster/' + line.strip(), names)
                addons = Path(temporary) / 'AddOns'
                archive.extractall(addons)
                self.assertTrue((addons / 'CraftRoster/CraftRoster.toc').is_file())
                self.assertEqual((addons / 'CraftRoster/Directory.lua').read_bytes(),
                                 (ROOT / 'Directory.lua').read_bytes())

