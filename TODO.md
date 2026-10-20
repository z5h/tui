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

# debug / profile mode
the old TUI_PROFILE render-time overlay was removed. revisit as a broader
mode: highlight regions being repainted, profile specific drawables or
the loop.
