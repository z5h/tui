# tui — Text User Interface framework for SWI-Prolog

A TUI framework inspired by TEA (The Elm Architecture). Define your app with a model, a view, and an update function.

## Installation

```prolog
?- pack_install(tui).
```

## Quick Start

```prolog
:- module(hello, []).
:- use_module(library(tui)).

:- initialization(main, main).

main :-
    app((1-1)-[], view, update, _).

view(_, "Hello, TUI!" .\/ "Press q to quit").

update(q, S, result(S)).
update(_, S, S).
```

Run with `swipl hello.pl`. The state is `(CursorX-CursorY)-Model`; update returns a new state, or `result(R)` to quit.

## Examples

In `examples/`, each runnable as `swipl -p library=prolog examples/NAME.pl` from a clone:

- `hello.pl` — the above
- `layout.pl` — the core drawables
- `events.pl` — a custom component, and tagging instances with `Key : Drawable`
- `cursor.pl` — the default cursor, and placing it from the view with `cursor/1`
- `gallery.pl` — the ready-made components
- `move.pl` — dragging with Shift+arrows, and `moved(Direction)`
- `atto.pl` — a small text editor: `swipl -p library=prolog examples/atto.pl -- FILE`

## Terminals

The ready-made components drag with Shift+arrows: what is under the cursor moves in the arrow's direction. macOS Terminal.app sends Shift+↑ and Shift+↓ as plain ↑ and ↓ by default. To fix it, in Settings → Profiles → Keyboard add:

- Shift+↑: Send Text `\033[1;2A`
- Shift+↓: Send Text `\033[1;2B`

Apps can work around a terminal's limits: shortly after starting, `update/3` receives `terminal_properties(Properties)`, holding `program(Program)` (from `TERM_PROGRAM`, e.g. `'Apple_Terminal'`, or `unknown`) and `extended_keys(Bool)` (whether modified keys are unambiguous, via the Kitty keyboard protocol). `examples/move.pl` uses it to show this caveat.

## Architecture

A single event loop in the main thread reads input, runs `update/3`, and paints the view. Painting is incremental: the view is grouped into runs of same-styled text, and only runs that changed since the last paint are written.

The loop talks to a *substrate*: a real terminal, or a VCR that replays a scripted conversation (events in, expected clears and paints out) so apps can be tested without a terminal. Other threads can deliver events through a wake pipe that the loop waits on alongside the terminal.

### Drawables

Views are built from a term-based DSL:

- **Primitives**: atoms, strings, numbers render as text; `literal(Term)` for any term
- **Layout**: `.>` (horizontal), `.<` (horizontal, right-aligned first), `.\/` (vertical), `./\` (vertical, bottom-aligned first)
- **Combinators**: `translate(DX-DY, D)`, `X-Y-D`, `port(W-H, D)`, `style(Attrs, D)`
- **Core drawables**: `row/1`, `column/1`, `wrapped(Width, Chars)`, `clear(W-H)`, `line(Char, From, To)`, `box(W-H, Chars)` (`thin`, `thick`, `double`, or your own characters), `hover(Style, D)`, `cursor(D)`
- **Components** (opt-in, `:- use_module(library(tui/components))`): `check_box/2`, `button/1`, `input/3`, `frame/2`, `titled_frame/3`, `scroll/3`
- **Tagging**: `Key : Drawable` — attaches an identity for event routing

### Custom Components

Define components via multifile hooks:

```prolog
tui:alias_drawable(my_widget(Label), style([bold], Label)).
tui:at_event_is(my_widget(_), _X-_Y-return, my_widget-activated).
```

A component sees each event with where it happened, relative to the component. It may rewrite an event in several ways (for example a new value, and `right` to advance the cursor); each reaches `update/3` in turn.

### Event Bubbling

Each screen coordinate tracks which components produced it (the alias stack). When an event occurs, it bubbles through the stack — each component can rewrite it via `tui:at_event_is/3`. The `:` tag operator namespaces events by component instance.

## Documentation

After loading the pack, browse the full API docs:

```prolog
?- doc_server(4000).
?- use_module(library(tui)).
```

Then open http://localhost:4000.

## License

MIT — see [./LICENSE](LICENSE).
