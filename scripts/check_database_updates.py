"""Watch public upstream data and prepare a review report; never execute fetched Lua.

Snapshots are observations, not approvals. The installed database is identified
independently by vendor/ProfessionDB/manifest.json. Network failures fail the run
before writing snapshots. Scheduled runs never replace the installed payload.
"""
import argparse
import base64
import html
import json
import os
from pathlib import Path
import re
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MAX_BYTES = 8 * 1024 * 1024
SHA = re.compile(r'^[0-9a-f]{40}$')
CF = 'https://www.curseforge.com/wow/addons/libprofessiondb'


def fetch(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or parsed.hostname not in {'api.github.com', 'www.curseforge.com'}:
        raise ValueError('Unsupported upstream URL')
    headers = {'User-Agent': 'CraftRoster-database-checker/1.0'}
    token = os.environ.get('GH_TOKEN')
    if parsed.hostname == 'api.github.com' and token:
        headers['Authorization'] = 'Bearer ' + token
    class SameHostRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, fp, code, msg, response_headers, new_url):
            target = urllib.parse.urlsplit(new_url)
            if target.scheme != 'https' or target.hostname != parsed.hostname:
                raise ValueError('Unexpected upstream redirect')
            return super().redirect_request(request, fp, code, msg, response_headers, new_url)
    opener = urllib.request.build_opener(SameHostRedirect())
    with opener.open(urllib.request.Request(url, headers=headers), timeout=30) as response:
        final = urllib.parse.urlsplit(response.url)
        if final.scheme != 'https' or final.hostname != parsed.hostname:
            raise ValueError('Unexpected upstream redirect')
        data = response.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError('Upstream response exceeds limit')
    return data.decode('utf-8')


def github(path, read=fetch):
    return json.loads(read('https://api.github.com/repos/' + path))


def professiondb_release(page):
    # Read file/version pairs from the publisher's links, not the largest unrelated ID.
    pairs = re.findall(r'href=["\'](?:https://www\.curseforge\.com)?/wow/addons/libprofessiondb/files/(\d+)["\'][^>]*>(.*?)</a>', page, re.S)
    found = {}
    for file_id, body in pairs:
        name = html.unescape(re.sub('<[^>]+>', ' ', body))
        version = re.search(r'ProfessionDB-(v\d+\.\d+\.\d+)\b', name)
        if version:
            found[int(file_id)] = version.group(1)
    if not found:
        raise ValueError('Cannot identify ProfessionDB publisher release; page format may have changed')
    file_id = max(found)
    return {'file_id': file_id, 'version': found[file_id], 'url': CF + '/files/' + str(file_id)}


def att_snapshot(config, ref=None, previous=None, read=fetch):
    repo, prefix = config['att_repository'], config['att_path']
    if ref is None:
        commits = github(repo + '/commits?' + urllib.parse.urlencode({'path': prefix, 'per_page': 1}), read)
        if not commits:
            raise ValueError('No Forever upstream commit')
        ref = commits[0]['sha']
    if not SHA.fullmatch(ref):
        raise ValueError('Expected an immutable upstream commit')
    parent, name = prefix.rsplit('/', 1)
    listing = github(repo + '/contents/' + urllib.parse.quote(parent, safe='/') + '?ref=' + ref, read)
    folders = [entry for entry in listing if entry['name'] == name and entry['type'] == 'dir']
    if len(folders) != 1:
        raise ValueError('Forever database folder missing')
    tree = github(repo + '/git/trees/' + folders[0]['sha'] + '?recursive=1', read)
    if tree.get('truncated'):
        raise ValueError('Incomplete upstream tree; refusing to infer removals')
    files = {entry['path']: entry['sha'] for entry in tree['tree']
             if entry['type'] == 'blob' and entry['path'].endswith('.lua')}
    if not files:
        raise ValueError('Empty Forever source tree')
    mappings = {}
    previous = previous or {}
    for path, blob in sorted(files.items()):
        if not path.startswith('profession db/'):
            continue
        if previous.get('files', {}).get(path) == blob:
            mappings[path] = previous.get('recipes', {}).get(path, {})
            continue
        data = github(repo + '/git/blobs/' + blob, read)
        if data.get('encoding') != 'base64':
            raise ValueError('Unexpected upstream blob format')
        source = base64.b64decode(data['content']).decode('utf-8-sig')
        # This reads IDs only. Upstream Lua and conditional expressions are never evaluated.
        pairs = re.findall(r'\bi\(\s*(\d+)\s*,\s*(\d+)\s*\)', source)
        rows = {}
        for item, spell in pairs:
            if int(item) > 0 and int(spell) > 0:
                rows.setdefault(spell, set()).add(int(item))
        mappings[path] = {spell: sorted(items) for spell, items in rows.items()}
    return {'commit': ref, 'files': files, 'recipes': mappings}


def flatten(snapshot):
    result = {}
    for rows in snapshot.get('recipes', {}).values():
        for spell, item in rows.items():
            result.setdefault(spell, set()).update(item if isinstance(item, list) else [item])
    return {spell: sorted(items) for spell, items in result.items()}


def changes(before, after):
    old, new = before['files'], after['files']
    old_recipes, new_recipes = flatten(before), flatten(after)
    return {
        'files_added': sorted(new.keys() - old.keys()),
        'files_removed': sorted(old.keys() - new.keys()),
        'files_changed': sorted(path for path in old.keys() & new.keys() if old[path] != new[path]),
        'recipes_added': sorted(new_recipes.keys() - old_recipes.keys(), key=int),
        'recipes_removed': sorted(old_recipes.keys() - new_recipes.keys(), key=int),
        'teaching_items_changed': sorted((spell for spell in old_recipes.keys() & new_recipes.keys()
                                         if old_recipes[spell] != new_recipes[spell]), key=int),
        'mapping_conflicts': sorted((spell for spell, items in new_recipes.items()
                                    if len(items) > 1 and old_recipes.get(spell) != items), key=int),
    }


def report(delta, old, new, bundled, config):
    old_recipes, new_recipes = flatten(old['att']), flatten(new['att'])
    lines = ['# Database update review', '',
             'This is an upstream change report. It does not approve locations or replace installed data.', '',
             '## ProfessionDB', '',
             f"Bundled: **{bundled['version']}**, file {bundled['curseforge_file_id']}, client build {bundled['client_data_build']}.",
             f"Publisher: **{new['professiondb']['version']}**, [file {new['professiondb']['file_id']}]({new['professiondb']['url']}).", '',
             'If the publisher file differs, review its Forever changelog and import its official ZIP with',
             '`scripts/update_profession_db.py` and an explicitly reviewed SHA-256. A version-only change is not proof of Forever changes.', '',
             '## AllTheThings Forever', '',
             f"Previous observation: `{old['att']['commit']}`.",
             f"New observation: `{new['att']['commit']}`.", '',
             'Recipe IDs below are catalogue mappings from source text. Conditional/hidden entries still require review.', '']
    for key, title in [('recipes_added', 'Added recipe IDs'), ('recipes_removed', 'Removed recipe IDs'),
                       ('teaching_items_changed', 'Changed teaching-item mappings'),
                       ('mapping_conflicts', 'Multiple teaching items requiring review'),
                       ('files_added', 'Added source files'), ('files_removed', 'Removed source files'),
                       ('files_changed', 'Changed source files')]:
        values = delta[key]
        lines += [f'### {title} ({len(values)})', '']
        for value in values:
            label = value.replace('`', '')
            if key.startswith('files_'):
                revision = old['att']['commit'] if key == 'files_removed' else new['att']['commit']
                path = urllib.parse.quote(config['att_path'] + '/' + value, safe='/')
                url = 'https://github.com/' + config['att_repository'] + '/blob/' + revision + '/' + path
                lines.append('- [`' + label + '`](' + url + ')')
            elif key == 'teaching_items_changed':
                lines.append(f"- Recipe `{label}`: {old_recipes[value]} → {new_recipes[value]}")
            else:
                lines.append('- `' + label + '`')
        if not values:
            lines.append('None.')
        lines.append('')
    lines += ['## Required review', '',
              '- Check exact Forever recipe, teaching-item and NPC IDs; do not join by names.',
              '- Review vendor coordinates, faction, reputation, quest and stock conditions in changed files.',
              '- Treat affected location records as needing review; do not automatically promote them to confirmed.',
              '- Changed files can affect materials, locations or conditions even when recipe IDs are unchanged.',
              '- Import approved data, update provenance, rebuild CraftRoster.zip and run addon tests before publishing.',
              '- Merging this report acknowledges a snapshot only. The bundled manifest remains the installed-data authority.', '']
    return '\n'.join(lines)


def run(root=ROOT, read=fetch, force_report=False):
    config = json.loads((root / 'data/database_watch.json').read_text())
    bundled = json.loads((root / 'vendor/ProfessionDB/manifest.json').read_text())
    snapshot_path = root / 'data/upstream_snapshot.json'
    if snapshot_path.exists():
        old = json.loads(snapshot_path.read_text())
    else:
        old = {'att': att_snapshot(config, config['att_baseline_commit'], read=read),
               'professiondb': {'file_id': bundled['curseforge_file_id'], 'version': bundled['version'], 'url': bundled['source_url']}}
    new = {'att': att_snapshot(config, previous=old['att'], read=read),
           'professiondb': professiondb_release(read(config['professiondb_url']))}
    delta = changes(old['att'], new['att'])
    changed = any(delta.values()) or new['professiondb'] != old['professiondb'] or force_report
    # Commit advancement without database changes must not create a daily PR.
    if changed:
        (root / 'docs/DATABASE_UPDATE_REPORT.md').write_text(report(delta, old, new, bundled, config))
        snapshot_path.write_text(json.dumps(new, indent=2, sort_keys=True) + '\n')
    elif not snapshot_path.exists():
        snapshot_path.write_text(json.dumps(new, indent=2, sort_keys=True) + '\n')
    return changed, delta


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--force-report', action='store_true', help='Prepare an audit even when upstream data is unchanged')
    args = parser.parse_args()
    changed, delta = run(args.root, force_report=args.force_report)
    print(json.dumps({'changed': changed, 'counts': {key: len(values) for key, values in delta.items()}}))
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write('changed=' + str(changed).lower() + '\n')
