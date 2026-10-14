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
some escape sequences for function keys and modifier combos are not
decoded properly. decide which terminal protocols to target, and decode
them properly.

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
