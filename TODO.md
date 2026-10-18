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
- not yet decoded: focus in/out.
- mouse: dragging a scroll's content (not just its thumb) needs to know
  where the drag came from; components are stateless, so it would need
  the loop's help (e.g. drags bubbling at the press point).
- a key-inspector example app (show codes and decoded events) would
  help diagnose terminals.

# escape sequence test
test the bytes terminal.pl produces (ansi_run/1 and the ansi_* helpers),
so the VCR can stay at the level of runs.

# async API
how apps receive events from other threads: export post/1 (loop.pl), or
have update/3 return TEA-style commands. timers fit either way: the
substrate's wait timeout becomes the time to the next deadline.

# debug / profile mode
the old TUI_PROFILE render-time overlay was removed. revisit as a broader
mode: highlight regions being repainted, profile specific drawables or
the loop.
