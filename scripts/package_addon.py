"""Build an installable ZIP containing only the top-level CraftRoster folder."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile
import argparse

ROOT = Path(__file__).resolve().parents[1]


def package(destination):
    source = ROOT
    manifest = source / 'CraftRoster.toc'
    for line in manifest.read_text().splitlines():
        entry = line.strip()
        if entry and not entry.startswith('#') and not (source / entry).is_file():
            raise ValueError(f'Missing addon module: {entry}')
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    entries = [line.strip() for line in manifest.read_text().splitlines()
               if line.strip() and not line.startswith('#')]
    paths = [manifest] + [source / entry for entry in entries]
    # Redistributed library notices and the pinned version record travel with
    # the addon; every runtime vendor file is listed explicitly in its TOC.
    paths += [source / 'vendor/ProfessionDB/LICENSE', source / 'vendor/ProfessionDB/manifest.json']
    with ZipFile(destination, 'w', ZIP_DEFLATED) as archive:
        for path in sorted(set(paths)):
            archive.write(path, 'CraftRoster/' + path.relative_to(source).as_posix())
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', nargs='?', default='dist/CraftRoster.zip')
    args = parser.parse_args()
    print(package(args.destination))

