# Contributing

Thanks for helping. Small, focused changes are easiest to review.

## Set up

You need a Mac with Xcode 16 or newer (or just the command line tools for the packages).

```bash
git clone https://github.com/Soham109/glasspad.git
cd glasspad
scripts/test.sh          # runs every package's tests
scripts/build-mac.sh     # builds build/Glasspad.app
scripts/live-check.sh    # tries the Mac features for real, by hand (docs/LIVE-CHECK.md)
```

For the iPhone app, run `xcodegen generate` and open the project in Xcode.

## Before you open a pull request

- Read [docs/SPEC.md](docs/SPEC.md). If you change an interface, change it in the spec too.
- `scripts/test.sh` must pass.
- Add a test for new behaviour. Gesture changes need a scripted touch sequence test.
- Tests must never post events into the live session.
- Keep gesture thresholds in `GestureTuning.swift`, not scattered in code.
- Any private macOS call needs a public fallback and a runtime check.
- Only public iOS APIs on the phone.
- Do not copy code from projects with incompatible licenses.

## Style

- Keep the interface minimal. No extra chrome on the trackpad screen.
- Plain words in docs and UI text. Explain any technical term where you use it.
- Do not use em dashes or en dashes in docs.

## Reporting bugs

Use the bug template. Include your macOS and iOS versions, phone model, and what the Mac menu says about native or fallback gestures.

## License

By contributing you agree your work is released under the [MIT license](LICENSE).
