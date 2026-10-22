"""Upstream changes must be reviewable, repeatable and fail without losing the baseline."""
import base64
import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('database_updates', ROOT / 'scripts/check_database_updates.py')
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)
OLD, NEW = 'a' * 40, 'b' * 40


def fixture(changed=True, fail=False, truncated=False):
    calls = []

    def read(url):
        calls.append(url)
        if url == updater.CF:
            if fail:
                raise OSError('publisher unavailable')
            return '<a href="/wow/addons/libprofessiondb/files/9095167">ProfessionDB-v1.9.1</a>'
        if '/commits?' in url:
            return json.dumps([{'sha': NEW}])
        if '/contents/' in url:
            return json.dumps([{'name': 'forever', 'type': 'dir', 'sha': 'oldtree' if 'ref=' + OLD in url else 'newtree'}])
        if '/git/trees/' in url:
            before = 'oldtree' in url
            return json.dumps({'truncated': truncated, 'tree': [
                {'path': 'profession db/leatherworking.lua', 'type': 'blob', 'sha': 'oldblob' if before or not changed else 'newblob'},
                {'path': 'zones/vendor.lua', 'type': 'blob', 'sha': 'zone1' if before or not changed else 'zone2'},
            ]})
        if '/git/blobs/' in url:
            source = 'i(10, 20); i(11, 21);'
            if url.endswith('newblob'):
                source = 'i(12, 20); i(13, 22); os.execute("DO NOT EXECUTE");'
            return json.dumps({'encoding': 'base64', 'content': base64.b64encode(source.encode()).decode()})
        raise AssertionError(url)
    return read, calls


class DatabaseUpdateTests(unittest.TestCase):
    def prepare(self, root):
        (root / 'data').mkdir()
        (root / 'docs').mkdir()
        (root / 'vendor/ProfessionDB').mkdir(parents=True)
        (root / 'data/database_watch.json').write_text(json.dumps({
            'att_repository': 'ATTWoWAddon/AllTheThings', 'att_path': '.contrib/.db/forever',
            'att_baseline_commit': OLD, 'professiondb_url': updater.CF}))
        (root / 'vendor/ProfessionDB/manifest.json').write_text(json.dumps({
            'version': 'v1.9.1', 'curseforge_file_id': 9095167,
            'client_data_build': '1.60.1.69977', 'source_url': updater.CF + '/files/9095167'}))

    def test_added_removed_changed_ids_and_locations_have_review_report(self):
        with TemporaryDirectory() as directory:
            root = Path(directory); self.prepare(root)
            read, _ = fixture()
            changed, delta = updater.run(root, read)
            self.assertTrue(changed)
            self.assertEqual(delta['recipes_added'], ['22'])
            self.assertEqual(delta['recipes_removed'], ['21'])
            self.assertEqual(delta['teaching_items_changed'], ['20'])
            self.assertIn('zones/vendor.lua', delta['files_changed'])
            report = (root / 'docs/DATABASE_UPDATE_REPORT.md').read_text()
            self.assertIn('not approve locations', report)
            self.assertIn('needs', report.replace('needing', 'needs'))
            self.assertIn('1.60.1.69977', report)
            self.assertIn('[10] → [12]', report)
            self.assertIn('https://github.com/ATTWoWAddon/AllTheThings/blob/' + NEW, report)
            self.assertEqual(json.loads((root / 'vendor/ProfessionDB/manifest.json').read_text())['version'], 'v1.9.1')

    def test_repeat_run_does_not_rewrite_or_refetch_unchanged_recipe_blobs(self):
        with TemporaryDirectory() as directory:
            root = Path(directory); self.prepare(root)
            read, calls = fixture()
            updater.run(root, read)
            report = root / 'docs/DATABASE_UPDATE_REPORT.md'
            before = report.stat().st_mtime_ns
            calls.clear()
            changed, _ = updater.run(root, read)
            self.assertFalse(changed)
            self.assertEqual(report.stat().st_mtime_ns, before)
            self.assertFalse(any('/git/blobs/' in url for url in calls))

    def test_commit_only_change_is_not_a_database_update(self):
        with TemporaryDirectory() as directory:
            root = Path(directory); self.prepare(root)
            read, _ = fixture(changed=False)
            changed, delta = updater.run(root, read)
            self.assertFalse(changed)
            self.assertFalse(any(delta.values()))
            self.assertFalse((root / 'docs/DATABASE_UPDATE_REPORT.md').exists())
            self.assertTrue((root / 'data/upstream_snapshot.json').exists())

    def test_requested_audit_can_generate_a_draft_without_inventing_changes(self):
        with TemporaryDirectory() as directory:
            root = Path(directory); self.prepare(root)
            read, _ = fixture(changed=False)
            changed, delta = updater.run(root, read, force_report=True)
            self.assertTrue(changed)
            self.assertFalse(any(delta.values()))
            self.assertIn('Added recipe IDs (0)', (root / 'docs/DATABASE_UPDATE_REPORT.md').read_text())

    def test_network_failure_never_advances_snapshot_or_report(self):
        with TemporaryDirectory() as directory:
            root = Path(directory); self.prepare(root)
            read, _ = fixture()
            updater.run(root, read)
            paths = [root / 'data/upstream_snapshot.json', root / 'docs/DATABASE_UPDATE_REPORT.md']
            before = [path.read_bytes() for path in paths]
            failing, _ = fixture(fail=True)
            with self.assertRaises(OSError):
                updater.run(root, failing)
            self.assertEqual(before, [path.read_bytes() for path in paths])

    def test_truncated_tree_never_reports_mass_removals(self):
        with TemporaryDirectory() as directory:
            root = Path(directory); self.prepare(root)
            read, _ = fixture(truncated=True)
            with self.assertRaisesRegex(ValueError, 'Incomplete'):
                updater.run(root, read)
            self.assertFalse((root / 'data/upstream_snapshot.json').exists())

    def test_publisher_parse_fails_closed_and_ignores_unrelated_numbers(self):
        with self.assertRaises(ValueError):
            updater.professiondb_release('<html>Cloudflare challenge</html>')
        page = ('<a href="/wow/addons/libprofessiondb/files/99999999">Screenshot</a>'
                '<a href="/wow/addons/libprofessiondb/files/9095167"><span>ProfessionDB-v1.9.1</span></a>')
        self.assertEqual(updater.professiondb_release(page)['file_id'], 9095167)

    def test_multiple_teaching_items_are_retained_and_flagged_for_review(self):
        snapshot = {'recipes': {'a.lua': {'42': [10, 12]}, 'b.lua': {'42': [11]}}, 'files': {}}
        self.assertEqual(updater.flatten(snapshot), {'42': [10, 11, 12]})
        delta = updater.changes({'recipes': {}, 'files': {}}, snapshot)
        self.assertEqual(delta['mapping_conflicts'], ['42'])

    def test_fetch_rejects_other_hosts_and_plain_http(self):
        for url in ('http://api.github.com/repos/a/b', 'https://example.com/data', 'file:///tmp/data'):
            with self.assertRaises(ValueError):
                updater.fetch(url)
