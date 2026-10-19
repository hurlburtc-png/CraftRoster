# Updating the bundled recipe database

Players install/update **CraftRoster only**. Its ZIP includes the pinned database,
so no separate ProfessionDB, Ace3 or VersionCheck installation is required.
The addon does not download code/data at login. Guild scans and ownership remain
in SavedVariables; replacing the addon folder does not require clearing them.

The database should be reviewed when Forever patches change recipes, the author
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

This is a release maintenance process, not automatic unreviewed replacement.
The original curated percentages remain explicitly Classic estimates. The library
supplies acquisition names, not drop percentages; unknown rates stay unknown.
