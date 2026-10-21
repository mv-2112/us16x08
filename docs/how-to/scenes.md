# Store and recall scenes

Scenes are ten slots stored **on this Mac, not in the unit**, in the **same file format as TASCAM's own panel**: Qt INI files `US-16x08_sm1.ini … sm10.ini` plus `US-16x08_SceneMemory.ini` for the names, kept in `~/Library/Application Support/US16x08Panel/Scenes/`.

- **Store / Recall / Clear / rename:** on the *Scenes* tab. Recall sends everything to the unit.
- **Import a scene from the official panel:** *Scenes* → a slot's **Import…** and pick its `US-16x08_smN` file, or **Import folder…** for all ten (names come from `US-16x08_SceneMemory`).
  The official panel keeps its files in `~/.config/TASCAM/` (a hidden folder: in the file picker press ⇧⌘G, type `~/.config/TASCAM`, or press ⇧⌘. to show hidden items). If you can't find them: `find ~ -name 'US-16x08_*' 2>/dev/null`.
- **Export:** **Export…** (one slot) or **Export all…** writes files the official panel's format describes.
- **Check an import:** the line under the buttons says how many values were applied; the Diagnostics Log keeps the same text.

**Extensions are not backwards compatible.** Anything the original panel doesn't have (the HCF high-cut, stored as `X_EqHighCutFilter`) is our own extension. The original ignores or may mishandle it, and we make no promise that files written by this app load in TASCAM's panel.
**Status of the format work:** key names were read from the original program. The exact meaning of the `…Pos` values was not confirmed on real files, so the importer prefers the `…Value` / `…Text` fields; please try a real file and report the result (see [KNOWN_ISSUES.md](../../KNOWN_ISSUES.md)).
