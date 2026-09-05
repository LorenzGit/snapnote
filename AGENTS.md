# Working on SnapNote

- Keep the local bundle identifier `local.snapnote.app` stable.
- Build the maintainer's local app with `bash scripts/build.sh`. Private signing configuration lives in ignored `scripts/signing.conf` and `scripts/signing.requirement` files. Never change that identity, fall back to ad-hoc signing, or publish those files. A missing Keychain identity is a build error, not a reason to replace the certificate.
- The explicit public `--unsigned` build mode uses ad-hoc signing only in a separate output directory. It must never replace the maintainer's signed app at `build/SnapNote.app`.
- Run `swift test --disable-sandbox` for behavior changes. Verify visible changes in the native app.
- When local signing/build scripts change, run `bash scripts/test-signing.sh` with Keychain access. Confirm the local designated requirement stays unchanged.
- Preserve unsaved work before restarting an updated local app. PNG backups flatten annotations; never claim they preserve editable objects.
- Public screenshots must use the built-in sample, with no personal desktop content. Keep scratch captures, build logs, credentials, and machine-specific paths out of Git.
- Never reset TCC globally or edit its database. macOS controls capture permissions.
