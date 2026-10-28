# input decoding
done: tui/input.pl decodes legacy xterm and the Kitty keyboard protocol,
which is detected and enabled at startup.
remaining:
- not yet decoded: focus in/out.
- a key-inspector example app (show codes and decoded events) would
  help diagnose terminals.

# commands
ports and subscriptions are done. optional, if wanted: update returning
State-Effects (TEA-style commands as data) so that an update with side
effects (e.g. sending to a worker) stays pure and testable, without
breaking plain State.

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

# jumping between units
from one button to the next with no intermediate state: right on OK
lands on Cancel, not on the gap between them. a unit/1 leaves by
cursor_by, which bubbles nothing, so nothing at the landing cell can
pass the cursor on. a skip/1 alias (the cursor passes through it on
arrived(Dir)) was tried and dropped: it only helps if leaving a unit
bubbles arrived where it lands, which is a loop change (and input/3
uses cursor_by to stay put after an edit, where no arrival is wanted).
perhaps better: move to the next unit in that direction directly.

# debug / profile mode
the old TUI_PROFILE render-time overlay was removed. revisit as a broader
mode: highlight regions being repainted, profile specific drawables or
the loop.
