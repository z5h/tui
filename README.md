# tui — Text User Interface framework for SWI-Prolog

A TUI framework inspired by TEA (The Elm Architecture). Define your app with a model, a view, and an update function.

## Installation

```prolog
?- pack_install(tui).
```

Requires SWI-Prolog 10.0 or later.

## Quick Start

```prolog
:- module(hello, []).
:- use_module(library(tui)).
:- use_module(library(tui/components)).

:- initialization(main, main).

main :-
    app((1-3)-none, view, update, Pressed, [mouse(true)]),
    format("You pressed ~w.~n", [Pressed]).

view(_, column(["Hello, TUI!",
                "",
                row([yes : button("Yes"), " ", no : button("No")])])).

update(yes-pressed, _, result('Yes')).
update(no-pressed, _, result('No')).
update(_, S, S).
```

Run with `swipl hello.pl`, and click a button (or move to it with the arrows and press space or return). The state is `(CursorX-CursorY)-Model`, here starting with the cursor on Yes and no model. Update returns a new state, or `result(R)` to end the app with result `R` (here `Pressed`). Each button is tagged with a key, so pressing it reaches update as `Key-pressed`.

View and update are called as by `once/1`. If either fails, the app ends with the error `tui_callback_failed(Which, State)` (Which is `update(Event)` or `view`), which a `catch/3` around `app` can report, or carry on from `State` in another app. Hence the last clause of `update/3` above, which leaves the state as it is for any other event.

`app/5` takes options as a last argument: `mouse(true)` turns on mouse reporting (see below), and `substrate(vcr(Script))` runs the app headless against a script (see Testing).

## Examples

The pack installs a `swipl tui` command for its examples:

```sh
swipl tui examples        # list them
swipl tui run gallery     # run one
swipl tui source gallery  # print its source
```

- `hello` — the above
- `layout` — the core drawables
- `align` — zones, aligns and tables
- `events` — a custom component, and tagging instances with `Key : Drawable`
- `cursor` — the default cursor, and placing it from the view with `cursor/1`
- `gallery` — the ready-made components, with the mouse
- `move` — dragging with Shift+arrows or the mouse, and `moved(Direction)`
- `image` — an image, through the Kitty graphics protocol
- `atto` — a small text editor: `swipl tui run atto FILE`

The examples are in the pack's `examples/` directory. From a clone, use `swipl app/tui.pl` in place of `swipl tui`; it runs the examples with the clone's library.

## Terminals

The ready-made components drag with Shift+arrows: what is under the cursor moves in the arrow's direction. macOS Terminal.app sends Shift+↑ and Shift+↓ as plain ↑ and ↓ by default. To fix it, in Settings → Profiles → Keyboard add:

- Shift+↑: Send Text `\033[1;2A`
- Shift+↓: Send Text `\033[1;2B`

Apps can work around a terminal's limits: shortly after starting, `update/3` receives `terminal_properties(Properties)`, holding `program(Program)` (from `TERM_PROGRAM`, e.g. `'Apple_Terminal'`, or `unknown`), `extended_keys(Bool)` (whether modified keys are unambiguous, via the Kitty keyboard protocol) and `graphics(Bool)` (whether images can be shown, via the Kitty graphics protocol). `examples/move.pl` uses it to show this caveat.

## Architecture

A single event loop in the main thread reads input, runs `update/3`, and paints the view. Painting is incremental: the view is grouped into runs of same-styled text, and only runs that changed since the last paint are written.

The loop talks to a *substrate*: a real terminal, or a VCR that replays a scripted conversation (events in, expected clears and paints out) so apps can be tested without a terminal. Other threads can deliver events through a wake pipe that the loop waits on alongside the terminal.

### Drawables

Views are built from a term-based DSL:

- **Primitives**: atoms, strings, numbers render as text; `literal(Term)` for any term
- **Layout**: `.>` (horizontal), `.<` (horizontal, right-aligned first), `.\/` (vertical), `./\` (vertical, bottom-aligned first)
- **Combinators**: `translate(DX-DY, D)`, `X-Y-D`, `port(W-H, D)`, `zone(W-H, D)`, `align(Direction, D)`, `style(Attrs, D)`
- **Styles**: `bold`, `faint`, `italic`, `underline`, `negative`, `crossed_out`; colours `fg(C)`, `bg(C)` and the bright `hfg(C)`, `hbg(C)`, C being `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, `default` or an index 0..255; and `fg(R, G, B)`, `bg(R, G, B)`
- **Alignment**: a zone has extent W×H whatever it draws, and an `align` directly in it (or in its list) is placed against its edges: `up_left`, `up`, `up_right`, `left`, `center`, `right`, `down_left`, `down`, `down_right`. The view is drawn in a zone the size of the terminal.
- **Core drawables**: `row/1`, `column/1`, `table(Style, Rows)` (`empty`, `space`, `thin`, `thick`, `double`; each cell is a zone), `wrapped(Width, Chars)`, `clear(W-H)`, `line(Char, From, To)`, `box(W-H, Chars)` (`thin`, `thick`, `double`, or your own characters), `hover(Style, D)`, `cursor(D)`
- **Components** (opt-in, `:- use_module(library(tui/components))`): `check_box/2`, `button/1`, `input/3`, `frame/2`, `titled_frame/3`, `scroll/3`
- **Tagging**: `Key : Drawable` — attaches an identity for event routing

### Mouse

With `app(State, View, Update, Result, [mouse(true)])`, the terminal reports the mouse. Events are `(X-Y)-mouse(Action, Button)` (Action `press`, `release`, `drag` or `move`; Button `left`, `middle`, `right`, ...) and `(X-Y)-mouse(scroll, Dir)`, with modifiers as for keys (`ctrl+mouse(press, left)`). A mouse event bubbles at its own position, so components see it relative to themselves; a press also moves the cursor there. The ready-made components take clicks, the wheel, and drags on a scrollbar. While reporting is on, select text with shift held (option on macOS). Off by default.

### Images

In terminals with the Kitty graphics protocol (Kitty, Ghostty), `image(Id, Source, W-H)` shows an image in W×H cells. Source is `png(Bytes)`, `rgba(PW-PH, Bytes)`, `rgb(PW-PH, Bytes)` (Bytes being octets, as read from a binary stream) or `file(Path)`. The image is uploaded once, and its cells behave like text: they can be clipped, overdrawn and erased. Draw images only once `update/3` receives `terminal_properties(Ps)` with `graphics(true)` in Ps. See `examples/image.pl`.

### Custom Components

Define components via multifile hooks:

```prolog
tui:alias_drawable(my_widget(Label), style([bold], Label)).
tui:at_event_is(my_widget(_), _X-_Y-return, my_widget-activated).
```

A component sees each event with where it happened, relative to the component. It may rewrite an event in several ways (for example a new value, and `right` to advance the cursor); each reaches `update/3` in turn.

### Event Bubbling

Each screen coordinate tracks which components produced it (the alias stack). When an event occurs, it bubbles through the stack — each component can rewrite it via `tui:at_event_is/3`. The `:` tag operator namespaces events by component instance.

## Testing

`app(State, View, Update, Result, [substrate(vcr(Script))])` runs an app without a terminal, against a script of what it receives and what it should paint:

- `send(Events)`: the next batch of events the app receives
- `expect(clear)`: the app clears the screen (it does on start and on every resize)
- `expect(runs(Runs))`: the app paints exactly Runs
- `expect(graphics(Actions))`: the app sends exactly these image uploads and placements, before the runs of the same paint

Entries are consumed in order. A run is `(X-Y)-(Attrs-Chars)`: 1-based screen coordinates, the style attributes, and the characters as a list of one-character atoms. Painting is incremental, so after the first paint `Runs` holds only the runs that changed (each whole), and erased cells appear as spaces. The cursor's cell is painted `negative`. Once the script is used up, every request for events gets `[eos]`, which a test app typically answers with `result(...)`. The terminal's properties are not reported unless the script sends them.

```prolog
:- use_module(library(tui)).
:- use_module(library(plunit)).

view(_-N, row(["Count: ", literal(N)])).

update(up, C-N0, C-N) :- !, N is N0 + 1.
update(eos, S, result(S)) :- !.
update(_, S, S).

:- begin_tests(counter).

test(counts) :-
    Script = [ send([terminal_size(20, 5)]),
               expect(clear),
               expect(runs([(1-1)-([]-['C', o, u, n, t, :, ' ', '0'])])),
               send([up, up]),
               expect(runs([(1-1)-([]-['C', o, u, n, t, :, ' ', '2'])]))
             ],
    app(_-0, view, update, Result, [substrate(vcr(Script))]),
    Result = _-2.

:- end_tests(counter).
```

Anything the app does that differs from the next entry throws `error(vcr_mismatch(Expected, Actual), _)`, with Actual written as the entry that would have matched. So you can also write an expectation as a placeholder, read the actual one from the failure, and check it before pasting it in.

## Documentation

After loading the pack, browse the full API docs:

```prolog
?- doc_server(4000).
?- use_module(library(tui)).
```

Then open http://localhost:4000.

## License

MIT — see [./LICENSE](LICENSE).

## On the use of an LLM

I designed and prototyped tui's core: the drawable DSL and commands, `alias_drawable/2` components, `at_event_is/3` rewriting and event bubbling through alias stacks. Commit `30db48f`, "pre claude refactor", is that prototype. Since then, most of the code has been written by Claude Code (Anthropic) under my direction: I set the architecture and requirements, made the design decisions (often choosing among or amending designs Claude proposed), and gave specific implementation guidance. The work is interactive and incremental: one change at a time, design changes discussed before they are made, and every change reviewed before the next. Commits with an LLM contribution carry a `Co-Authored-By: Claude` trailer. The library has headless tests, run by CI on the stable and development releases of SWI-Prolog, and its terminal features have been checked by hand in real terminals.
