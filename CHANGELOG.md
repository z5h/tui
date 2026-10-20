# Changelog

`version/1` in `pack.pl` is the version. Releases are tagged `V<version>`.

## 0.2.0

### Changed (may break apps)

- **What is written to `user_error` now reaches update as `stderr(Text)` events**, a line at a time, instead of the screen, where it garbled the app. This covers messages and warnings, `debug/3`, `make/0`'s report, and plain writes to `user_error`, from any thread. It applies only in a terminal session; the headless VCR is unaffected.
  - An update without a catch-all clause now fails on `stderr(Text)`, which ends the app with `tui_callback_failed(update(stderr(Text)), State)`. Add `update(_, S, S).` as the last clause, as the examples do.
  - Text written to `user_error` while an app runs is no longer printed anywhere unless the app shows or logs it.

### Added

- `app/5` option `reload(Key)`: hot reloading. Key runs `make/0`, paints the view as the new code draws it, keeping the state, then update receives `reloaded`. Key reaches neither components nor update.
- `app/5` option `redraw(Key)`: Key clears the screen and paints the view again. Key reaches neither components nor update.
- `examples/reload.pl`: edit it while it runs and press F5; it shows its stderr.
- README: hot reloading and its caveats; standard error; a subscription that turns `print_message/2` messages into events through `user:message_hook/3`.

### Documented

- Atoms, strings and numbers always draw as text: an alias must be a compound term. A component without arguments is written `name()`, e.g. `tui:alias_drawable(logo(), D)`. (Unchanged behaviour; now stated in `alias_drawable/2` and the README.)

## 0.1.2

- The repository moved to https://github.com/z5h/tui.

## 0.1.1

- Documentation is PLDoc throughout, checked by a test.

## 0.1.0

First published release.
