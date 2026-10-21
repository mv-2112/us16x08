# Check the unit with the command-line tool

Run from the project folder. Quit the panel first (one client at a time).

| Goal | Command |
|---|---|
| Is the unit visible? | `swift run us16x08ctl list` |
| Read-only handshake | `swift run us16x08ctl probe` |
| Firmware version | `swift run us16x08ctl firmware` |
| Watch input levels (dBFS) for 10 s | `swift run us16x08ctl meters 10` |
| Guided test where you listen | `swift run us16x08ctl selftest` |
| Automatic loopback test (plays audio!) | `swift run us16x08ctl autotest --level=-24` |
| Run the unit tests | `swift test` |

Add `--dry-run` to any command to print the bytes instead of sending them. All commands: [CLI reference](../reference/cli.md).
