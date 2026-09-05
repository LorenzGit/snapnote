# Contributing

Open an issue describing the problem or proposed change before a large feature.
Small bug fixes are welcome as pull requests.

Requires macOS 14 or later and Xcode with Swift 5.9 or later. No third-party packages are used.

```sh
swift test --disable-sandbox
bash scripts/build.sh --unsigned
```

The unsigned build is separate from locally signed development builds. See the README for launch instructions and signing limitations.

For UI changes, include a screenshot or short recording using the built-in sample. Check drawing, undo/redo, keyboard shortcuts, and clipboard/PNG output. Do not include private screenshots, local signing files, certificates, or personal filesystem paths.

Keep changes focused. Contributions are licensed under the MIT license in this repository.
