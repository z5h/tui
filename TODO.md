# make scrolling better
currently, scrolling, and page up/down code shares some logic, but also
we can't page up/down when ON a scroll bar.
refactor, simplify.

# revisit focus/hover
make it so a style element can have hover(style) and that is when it is applied.
under the hood, we'll do hover(style, Group), then process the list
to map hover(style,true) -> style, and to remove the others

hover currently leaks into drawable.pl: is_attribute/1 accepts
style_hovergroup (commented there).

# input decoding
done: tui/input.pl decodes legacy xterm and the Kitty keyboard protocol,
which is detected and enabled at startup.
remaining:
- macOS Terminal.app sends shift+up/down as plain up/down by default
  (only shift+left/right have modified sequences), so they cannot be
  told apart. users can add \033[1;2A / \033[1;2B in Profiles > Keyboard.
- not yet decoded: mouse (SGR 1006), bracketed paste, focus in/out.
- a key-inspector example app (show codes and decoded events) would
  help diagnose terminals.

# escape sequence test
test the bytes terminal.pl produces (ansi_run/1 and the ansi_* helpers),
so the VCR can stay at the level of runs.

# public API for headless testing
decide whether library(tui) should export app/5 and document the VCR, so
users can test their own apps. tests currently import app/5 from
library(tui/loop).

# async API
how apps receive events from other threads: export post/1 (loop.pl), or
have update/3 return TEA-style commands. timers fit either way: the
substrate's wait timeout becomes the time to the next deadline.

# debug / profile mode
the old TUI_PROFILE render-time overlay was removed. revisit as a broader
mode: highlight regions being repainted, profile specific drawables or
the loop.

# merge single-threaded-loop into main
