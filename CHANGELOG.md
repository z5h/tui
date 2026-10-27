# Changelog

`version/1` in `pack.pl` is the version. Releases are tagged `V<version>`.

## Unreleased

### Changed (may break apps)

- **Nested styles: the innermost now wins.** In `style(Outer, style(Inner, D))`, Inner was applied first and Outer last, so Outer won: `style([fg(red)], style([fg(blue)], a))` showed red, and an outer `reset` cancelled every style inside it. Inner is now applied last. A component's own styles are no longer overridden by the styles around it; to restyle a whole view, change its commands' attributes.
- **`reset` is no longer a style attribute.** Each run is painted from the default style anyway, and with the innermost winning, an inner `reset` could only cancel the styles around it. Leave it out, or set the attributes wanted.
- **`clear(W-H)` draws its spaces in the enclosing style**, instead of resetting it: it covers what is under it with the surrounding background, unless a background is set explicitly.
- **The components are restyled** (`library(tui/components)`, design in `QUIET_GRID.md`). Focus is shown negative instead of bold, and faint no longer marks unset values:
  - `frame/2-3`, `titled_frame/3-4`: rules across the full width above and below, no side walls; the viewport is still (W-2)×(H-2) from 1-1, between blank columns. The whole frame is cleared. The title sits in the top rule from its first column, without the `╴ ╶` ends.
  - `button/1`: `┃Label┃`, and focused a negative `▌Label▐`, instead of `[ Label ]`.
  - `check_box/2`: `[x] Title` instead of `[x]: Title`, in normal video whether checked or not. A third value, `partial`, shows `[-]` and toggles to `true`.
  - Buttons and check boxes hide the cursor, and left and right move it out of them in one keypress.
  - `input/3`: a bold `> `; the placeholder in angle brackets, italic. Focused, prompt and field are negative and the field loses its underline; the placeholder is then not shown.
  - `scroll/3`: only the thumb is drawn, no track: in the frame's right column (right-half blocks) and in its bottom rule (lower-half blocks, still underlined).

### Added

- `char(C)` as a style attribute: every cell drawn under it shows the character C (one column wide) in place of what was drawn. The innermost wins. Its main use is in a hover style, where glyphs change on focus: hovers sharing a group variable, `hover(Style, D, Group)`, turn on together.
- `cursor_hidden` as a style attribute: the cursor is not shown on cells drawn under it. It keeps its position, and events bubble as before; only its highlight is not drawn (cells drawn by `highlight/1` still are). For components that move the cursor out in one keypress, such as buttons.
- `unhovered(Style, D, Group)`: the other state of `hover(Style, D, Group)`. Style applies while the group is off, and is dropped when the cursor turns it on.
- `rule(Width)` (components): a horizontal rule, spaces drawn underlined.
- `examples/gallery.pl`: laid out for 80×24, with a partial check box and a status line (the last event, and key hints).

### Removed

- The unused `conceal` and `reveal` handling, and the `hide_cursor` attribute. No drawable could use them: they were not accepted as attributes. `char(' ')` conceals.

## 0.2.1

### Fixed

- The cursor was invisible on a cell already drawn `negative`. It now highlights its cell as `highlight/1` does: `negative` is added, or removed if the cell has it; a negative space with no underline on the default background, which would then be blank, is underlined instead.

### Added

- `highlight(D)`: draws D with each cell highlighted as the cursor's is. Nested highlights, and the cursor on a highlighted cell, highlight once.
- `examples/ink.pl`: an editor for text styled with ANSI escapes. A file is replayed onto an 80-column screen (cursor movement and SGR) and saved as styled rows that `cat` shows. Overwrite typing, rectangular selection, styles toggled or set per cell, copy, cut and paste of styled cells.

### Documented

- `CONSIDERATIONS.md`: ISO Prolog compatibility, what is incompatible and what is only not supported, and how that was determined.
- `TODO.md`: wide characters (CJK, most emoji) are taken to be one cell wide, so they misplace what follows them on a row.

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
