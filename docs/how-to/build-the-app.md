# Build and install the app

Prerequisite: full Xcode (see the README's *Prerequisites*).

```
swift build                    # compile
swift test                     # protocol and logic tests
swift run US16x08Panel         # try it without bundling
./Scripts/make_app.sh          # build/US16x08 Panel.app (arm64, ad-hoc signed)
./Scripts/fetch_license.sh     # once, before distributing: installs the full GPL text
```
Drag the `.app` to Applications. On first launch right-click → Open, because it is ad-hoc signed.
If the window opens at an old size, the app resets saved window frames automatically when the layout version changes.
