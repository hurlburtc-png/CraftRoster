"""Build an installable ZIP containing only the top-level CraftRoster folder."""
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile
import argparse

ROOT = Path(__file__).resolve().parents[1]


def package(destination):
    source = ROOT / 'CraftRoster'
    manifest = source / 'CraftRoster.toc'
    for line in manifest.read_text().splitlines():
        entry = line.strip()
        if entry and not entry.startswith('#') and not (source / entry).is_file():
            raise ValueError(f'Missing addon module: {entry}')
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(destination, 'w', ZIP_DEFLATED) as archive:
        for path in sorted(source.rglob('*')):
            if path.is_file() and not any(part.startswith('.') or part == '__pycache__'
                                          for part in path.relative_to(source).parts):
                archive.write(path, path.relative_to(ROOT).as_posix())
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', nargs='?', default='dist/CraftRoster.zip')
    args = parser.parse_args()
    print(package(args.destination))
