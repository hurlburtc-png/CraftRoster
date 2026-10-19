"""Exercise the actual pinned library/data without external addons."""
import hashlib
import importlib
import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'vendor/ProfessionDB'
LOCK = json.loads((VENDOR / 'manifest.json').read_text())


class BundledDatabaseTests(unittest.TestCase):
    def load(self, runtime, locale='enUS', interface=16001):
        lua = importlib.import_module('lupa.' + runtime).LuaRuntime(unpack_returned_tuples=True)
        lua.execute((ROOT / 'tests/wow_mock.lua').read_text())
        lua.globals().fixtureLocale = locale
        lua.globals().fixtureInterface = interface
        lua.execute('function GetLocale() return fixtureLocale end; '
                    'function GetBuildInfo() return "test", "0", "today", fixtureInterface end')
        for name in LOCK['load_order']:
            lua.compile((VENDOR / name).read_text(), name=name)('CraftRoster', lua.table())
        return lua

    def test_actual_forever_payload_in_all_shipped_locales(self):
        locales = [Path(name).stem for name in LOCK['load_order']
                   if '/_core/' not in name and name.startswith('Data/')]
        self.assertEqual(len(locales), 12)
        for runtime in ('lua51', 'luajit21'):
            for locale in locales:
                with self.subTest(runtime=runtime, locale=locale):
                    lua = self.load(runtime, locale)
                    lua.execute('''
                        local db=LibStub('LibProfessionDB-1.0')
                        assert(db:IsReady() and db:GetGameVersion()=='Forever')
                        assert(db:Count()==2511 and #db:GetProfessions()==10)
                        local recipe=db:GetRecipe(171,17635)
                        assert(type(recipe.name)=='string' and #recipe.name>0)
                        assert(db:GetRecipeItem(17635)==13519)
                        assert(db:GetRecipeItem(19054)==15730)
                        assert(db:IsBorrowed(17635,'sources')=='Vanilla')
                        assert(db:GetRecipeSources(17635).drop.total>0)
                        assert(not AceAddon and not AceComm and not VersionCheck)
                    ''')

    def test_other_clients_never_receive_forever_recipes(self):
        for runtime in ('lua51', 'luajit21'):
            for interface in (11509, 16002, 20506, 60000, 120100):
                with self.subTest(runtime=runtime, interface=interface):
                    lua = self.load(runtime, interface=interface)
                    lua.execute("assert(not LibStub('LibProfessionDB-1.0'):IsReady()); "
                                "assert(LibStub('LibProfessionDB-1.0'):Count()==0)")

    def test_shared_libstub_repeat_load_preserves_counts_and_local_data(self):
        for runtime in ('lua51', 'luajit21'):
            lua = self.load(runtime)
            for name in LOCK['load_order']:
                lua.compile((VENDOR / name).read_text())('CraftRoster', lua.table())
            lua.execute('''
                local db=LibStub('LibProfessionDB-1.0')
                assert(db:Count()==2511)
                assert(db:GetRecipe(171,17635).name=='Flask of the Titans')
                assert(db:GetRecipeItem(17635)==13519)
            ''')

    def test_vendor_bytes_and_toc_are_locked(self):
        toc = (ROOT / 'CraftRoster.toc').read_text().splitlines()
        self.assertEqual([line for line in toc if line.startswith('vendor/')],
                         ['vendor/ProfessionDB/' + name for name in LOCK['load_order']])
        for name, expected in LOCK['files'].items():
            self.assertEqual(hashlib.sha256((VENDOR / name).read_bytes()).hexdigest(), expected, name)
        actual = {p.relative_to(VENDOR).as_posix() for p in VENDOR.rglob('*') if p.is_file()}
        self.assertEqual(actual, set(LOCK['files']) | {'manifest.json'})
        self.assertIn('Copyright (c) 2026 Pimptasty', (VENDOR / 'LICENSE').read_text())

    def test_import_is_repeatable_and_refuses_wrong_archive(self):
        spec = importlib.util.spec_from_file_location('vendor_db', ROOT / 'scripts/update_profession_db.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            archive = temporary / 'release.zip'
            with ZipFile(archive, 'w') as release:
                release.writestr('ProfessionDB/ProfessionDB_Camelot.toc',
                                 '## Interface: 16001\n## Version: ProfessionDB-v1.9.1\n'
                                 'Data\\Forever\\_core\\Alchemy.lua\nData\\Forever\\enUS\\Alchemy.lua\n')
                release.writestr('ProfessionDB/libs/LibStub/LibStub.lua', '-- stub\n')
                release.writestr('ProfessionDB/LibProfessionDB-1.0.lua',
                                 'local MAJOR, MINOR = "LibProfessionDB-1.0", 13\n')
                release.writestr('ProfessionDB/LICENSE', (VENDOR / 'LICENSE').read_bytes())
                release.writestr('ProfessionDB/Data/Forever/_core/Alchemy.lua', '-- build 1.60.1.69977\n')
                release.writestr('ProfessionDB/Data/Forever/enUS/Alchemy.lua', 'if GetLocale()~="enUS" then return end\n')
            checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
            first, second = temporary / 'first', temporary / 'second'
            module.vendor(archive, 'v1.9.1', 9095167, checksum, first)
            module.vendor(archive, 'v1.9.1', 9095167, checksum, second)
            for path in first.rglob('*'):
                if path.is_file():
                    self.assertEqual(path.read_bytes(), (second / path.relative_to(first)).read_bytes())
            before = (first / 'manifest.json').read_bytes()
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                module.vendor(archive, 'v1.9.1', 9095167, '0' * 64, first)
            with self.assertRaisesRegex(ValueError, 'version'):
                module.vendor(archive, 'v9.9.9', 9095167, checksum, first)
            self.assertEqual((first / 'manifest.json').read_bytes(), before)
