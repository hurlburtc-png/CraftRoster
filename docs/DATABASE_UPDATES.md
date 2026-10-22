# Updating the bundled recipe database

Players install/update **CraftRoster only**. Its ZIP includes the pinned database,
so no separate ProfessionDB, Ace3 or VersionCheck installation is required.
The addon does not download code/data at login. Guild scans and ownership remain
in SavedVariables; replacing the addon folder does not require clearing them.

## Automatic online checks

The **Check online recipe databases** GitHub workflow runs daily at 09:17 UTC,
can be run with **Run workflow**, and runs when its checker/configuration changes.
It monitors the official ProfessionDB publisher page and AllTheThings' Forever
source tree. It does not scrape Wowhead or rely on a private API key.
Checks discover changes when those upstream projects publish them; they cannot
detect an unpublished Blizzard change immediately.
The first push, and later checker/configuration changes, request an audit even
when source data is unchanged, to exercise the review path without inventing changes.

The checker compares immutable source revisions, added/removed recipe IDs,
teaching-item mappings and changed acquisition files. It retains multiple
teaching-item mappings for review, ignores placeholder IDs, refuses truncated
trees, and fails without advancing the snapshot when a source cannot be read.
Commit changes outside the watched data do not create an update report.

When a change is found it runs the addon tests, retains a report artifact and
opens/updates a **draft** PR on `automation/recipe-database-update`. Repeated runs
with the same snapshot do not create duplicate PRs. Human changes to that branch
stop the bot from overwriting it. Nothing is automatically merged or released.
The repository must allow GitHub Actions to create pull requests; a policy block
is reported by the workflow and the report remains available as an artifact.

`data/upstream_snapshot.json` records the last **observed** upstream state.
It is not an approval and is not shipped in the addon. The separate
`vendor/ProfessionDB/manifest.json` identifies the database actually installed.
Merging a report alone does not update any recipes, locations or ZIP contents.

For a data update, complete the import/review steps below on the draft branch (or
a separate review branch), including its regenerated ZIP. A ProfessionDB version
can change only other game clients, so inspect its Forever changes before import.
For an affected location, verify the exact recipe/teaching-item/NPC IDs, faction,
coordinates and source conditions in Forever-specific online data. Borrowed or
conflicting data remains unconfirmed; a changed hash is a review trigger, never
confirmation. Include source URL, revision, checked date and applicable build when
known. Do not invent a build or drop percentage. Players receive approved data by
updating CraftRoster after the reviewed changes are published.

Local check (no GitHub writes):

```sh
python scripts/check_database_updates.py
```

The database should also be reviewed when Forever patches change recipes, the author
publishes a relevant release, or a confirmed discrepancy is reported. Not every
CraftRoster change requires a database update, and a newer library release may
change only Retail data. Update the complete compatible Forever snapshot, not
individual copied recipe rows. Keep corrections to CraftRoster's curated rates
separate, with their own source and uncertainty labels.

## Maintainer procedure

1. Read the official [release page](https://www.curseforge.com/wow/addons/libprofessiondb/files/9095167)
   and changelog. Check Forever support, client build, API changes, licensing and
   newly borrowed values. A newer version is not evidence of confirmed loot rates.
2. Download the official release ZIP. Record its file ID and SHA-256. Compare an
   authoritative checksum when one is published; a locally computed checksum
   pins the reviewed bytes but alone does not prove publisher authenticity.
3. Run the importer against that local archive. Current pinned example:

   ```sh
   python scripts/update_profession_db.py --archive /path/to/ProfessionDB-ProfessionDB-v1.9.1.zip --version v1.9.1 --file-id 9095167 --sha256 909cb41720cf6bf6920f1c25c644f89b39ad63087f589c07737e7da943c52379
   ```

   This vendors only the library and Forever data, preserves the license, combines
   locale chunks without changing their scope, and records archive/per-file
   checksums and original member hashes in `vendor/ProfessionDB/manifest.json`.
   It checks the expected release version, interface and license before writing.
   Interface/license changes require reviewing the importer first.
4. Review the entire diff. Match the TOC vendor entries to the manifest's
   `load_order` if upstream added/removed files. Update expected counts/builds
   only after explaining their changes. Update this document's pin and source
   notes. Do not hand-edit generated vendor data or erase borrowed-value flags.
5. Rebuild `CraftRoster.zip`, then run:

   ```sh
   python scripts/package_addon.py CraftRoster.zip
   python -m unittest discover -s tests -v
   python tests/benchmark.py
   ```

   Review actual client detection, every locale, teaching-item mappings, rank
   books, source flags, repeated LibStub loads, payload hashes, ZIP contents and
   licenses. Test coexistence with other addons embedding the library in-game;
   a shared LibStub API version does not identify the date of every data record.
6. Check tooltips/binding and a sample of trainer/vendor/drop recipes in Forever,
   with existing SavedVariables and two guild clients. Confirm ownership is not
   invented, and verify recipe-list, shopping and request behavior still works.
7. Ship the addon source, manifest, tests, documentation and rebuilt ZIP together
   in one reviewed CraftRoster commit/release. GitHub CI must pass. Record the
   library version/client build in release notes. Retain the previous working
   release for rollback; do not roll back a player's SavedVariables blindly.

Online detection is automatic; importing and publishing changed data remains reviewed.
The original curated percentages remain explicitly Classic estimates. The library
supplies acquisition names, not drop percentages; unknown rates stay unknown.
