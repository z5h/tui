# input decoding
done: tui/input.pl decodes legacy xterm and the Kitty keyboard protocol,
which is detected and enabled at startup.
remaining:
- not yet decoded: focus in/out.
- mouse: dragging a scroll's content (not just its thumb) needs to know
  where the drag came from; components are stateless, so it would need
  the loop's help (e.g. drags bubbling at the press point).
- a key-inspector example app (show codes and decoded events) would
  help diagnose terminals.

# commands
ports and subscriptions are done. optional, if wanted: update returning
State-Effects (TEA-style commands as data) so that an update with side
effects (e.g. sending to a worker) stays pure and testable, without
breaking plain State.

# documenting drawables
drawables and aliases (row/1, column/1, cursor/1, clear/1, box/2,
image/3, the components, ...) are documented with %! as if they were
predicates. they are terms, not predicates, so the PLDoc server shows
them in red (no predicate found). find a way to document them as terms:
e.g. a section of the module comment, or a documented type/predicate
that enumerates them.

# wide characters
a char is assumed to take one cell everywhere: drawables, render runs,
wrapped/2, atto's columns. wide chars (CJK, most emoji) take two cells
and zero-width ones (combining marks, ZWJ, variation selectors) none, so
they currently misplace everything after them on the row. needs a
char-width relation (wcwidth-like) used by layout, cell resolution and
the cursor.

# ascii glyph fallback
the components (QUIET_GRID.md) use Unicode glyphs only. an ASCII
fallback, for terminals or fonts without them (the Linux text console,
a non-UTF-8 locale), would need a choice of glyph set, and a way to make
it (detected, or an option).

# debug / profile mode
the old TUI_PROFILE render-time overlay was removed. revisit as a broader
mode: highlight regions being repainted, profile specific drawables or
the loop.
