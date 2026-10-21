# Files and settings

| What | Where |
|---|---|
| Last-sent state | `~/Library/Application Support/US16x08Panel/state.json` |
| Scenes | `~/Library/Application Support/US16x08Panel/Scenes/US-16x08_sm1…10.ini` + `US-16x08_SceneMemory.ini` (TASCAM's format; older `scenes.json` is migrated once) |
| Appearance | UserDefaults key `appearance` (auto, light, dark) |
| Window frame | macOS autosave; reset automatically when the layout version changes |
| Reports | `us16x08-selftest-report.txt`, `us16x08-autotest-report.txt` in the current folder |
| Licence & credits | `COPYING`, `NOTICE.md`, About window |

Delete `state.json` to return the panel to factory defaults.
