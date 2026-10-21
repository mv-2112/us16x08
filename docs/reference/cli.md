# us16x08ctl commands

`swift run us16x08ctl <command> [args] [--dry-run]`

| Command | Purpose |
|---|---|
| `list` | USB devices matching 0644:8047 |
| `info` | Descriptor details, sample rate |
| `firmware` | Version, build, product, build date/time via the unit's query |
| `probe` | Read-only handshake |
| `meters [seconds]` | Print input levels in dBFS |
| `dump` | Print the full state as protocol bytes |
| `fader`, `pan`, `mute`, `phase`, `master-fader`, `master-mute`, `bypass`, `bus-out`, `route`, `eq-enable`, `eq`, `comp` | Send one control |
| `selftest` | Guided, you listen; writes `us16x08-selftest-report.txt` |
| `autotest [--level=dBFS] [--yes]` | Plays tones and checks 21 behaviours from the meters; writes `us16x08-autotest-report.txt` |

Run a command with no arguments for its usage line.
