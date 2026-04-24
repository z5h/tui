# tui — Text User Interface framework for SWI-Prolog

A TUI framework inspired by TEA (The Elm Architecture). Define your app with a model, a view, and an update function.

## Installation

```prolog
?- pack_install(tui).
```

## Quick Start

```prolog
:- module(hello, [go/0]).
:- use_module(library(tui)).

:- op(601, xfy, '.\\/').

view(_State, "Press q to quit" .\/ "Hello, TUI!").

update(q, State, result(State)).
update(_, State, State).

go :-
    app(1-1-[], view, update, _Result).
```

Run with `swipl -g go hello.pl`.

## Architecture

Three threads cooperate: the **main thread** reads terminal input, the **update thread** processes events and generates views, and the **tty_output thread** serializes writes to the terminal.

### Drawables

Views are built from a term-based DSL:

- **Primitives**: atoms, strings, numbers render as text; `literal(Term)` for any term
- **Layout**: `.>` (horizontal), `.<` (horizontal, right-aligned first), `.\/` (vertical), `./\` (vertical, bottom-aligned first)
- **Combinators**: `translate(DX-DY, D)`, `X-Y-D`, `port(W-H, D)`, `style(Attrs, D)`
- **Builtins**: `box(W-H, Style)`, `clear(W-H)`, `hover(Style, D)`
- **Components**: `column/1`, `row/1`, `check_box/2`, `input/3`, `frame/2`, `titled_frame/3`, `scroll/3`
- **Tagging**: `Key : Drawable` — attaches an identity for event routing

### Custom Components

Define components via multifile hooks:

```prolog
tui:alias_drawable(my_widget(Label), style([bold], Label)).
tui:at_event_is(my_widget(_), return, my_widget-activated).
```

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

MIT — see [LICENSE](LICENSE).
