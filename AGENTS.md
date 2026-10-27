# AGENTS.md

This file provides guidance to coding agents working with code in this repository.

## Overview

A Text User Interface (TUI) framework for SWI-Prolog, inspired by TEA (The Elm Architecture). Apps are defined with `app/4` accepting a model, view callback, update callback, and final-result argument.

## Pack Structure

This is a SWI-Prolog pack. Library modules live in `prolog/`, internal modules in `prolog/tui/`.

- `prolog/tui.pl` — public module `tui`: a facade of operators, re-exports, and the hook declarations (auto-loads components)
- `prolog/tui/utils.pl` — `tui_utils`: `goals_attempted/1` (for cleanups: every step is tried, failures are warnings), list/DCG helpers, direction and limits geometry. Depends on nothing.
- `prolog/tui/terminal.pl` — `tui_terminal`: generic ANSI output (`ansi_*`, `ansi_run/1`, styles encoded by `attributes_sgr/2`, independent of `library(ansi_term)` and its `color_term` flag), device-attributes and Kitty keyboard and graphics queries. The `terminal` test unit checks the bytes
- `prolog/tui/input.pl` — `tui_input`: decodes terminal input codes into events (legacy xterm and Kitty keyboard protocol), with no side effects
- `prolog/tui/drawable.pl` — `tui_drawable`: the drawable DSL (`drawable//5`), attributes, commands, cell resolution (`char/1`), and the core drawables that make no styling choices: `row/1`, `column/1`, `table/2`, `wrapped/2`, `clear/1`, `line/3`, `box/2`, `Key:Drawable` tagging, `cursor/1`
- `prolog/tui/hover.pl` — `tui_hover`: the `hover/2` component and cursor-dependent hover styling
- `prolog/tui/image.pl` — `tui_image`: `image/3` (Kitty graphics placeholders) and which uploads and placements a frame needs (design: `CONSIDERATIONS.md`)
- `prolog/tui/events.pl` — `tui_events`: event bubbling through component stacks, the event map
- `prolog/tui/render.pl` — `tui_render`: commands → runs, and which runs changed (no side effects)
- `prolog/tui/wake.pl` — `tui_wake`: a message queue that `wait_for_input/3` can wait on
- `prolog/tui/subscriptions.pl` — `tui_subscriptions`: the app's port (`port_send/2`) and its subscriptions (`every/2`, `thread/1`), started and stopped as the state calls for
- `prolog/tui/substrate.pl` — `tui_substrate`: what the loop draws onto and gets events from (`terminal` or `vcr(Script)`)
- `prolog/tui/vcr.pl` — `tui_vcr`: scripted replay for headless tests
- `prolog/tui/loop.pl` — `tui_loop`: `app/4`, `app/5` and the event loop
- `prolog/tui/components.pl` — `tui_components`: ready-made, styled components (opt-in, not loaded by `library(tui)`)
- `prolog/tui/assocs.pl` — `tui_assocs`
- `examples/` — one topic each: `hello.pl`, `layout.pl`, `align.pl`, `events.pl`, `cursor.pl`, `gallery.pl` (the components), `move.pl`, `image.pl`, `async.pl` (subscriptions: a timer and a worker thread), `reload.pl` (hot reloading, stderr events). Test files must not load examples: their `initialization(main, main)` would run the app
- `examples/atto.pl` — atto, a tiny text editor: key bindings and view; `examples/atto_lib.pl` is its editing model (document, cursor, scrolling, files), driven by commands
- `examples/ink.pl` — ink, an editor for ANSI-styled text on an 80-column screen: key bindings and view; `examples/ink_lib.pl` is its editing model (cells, rectangular selection, styles, clipboard, files), and `examples/sgr_screen_lib.pl` replays a file's text (cursor movement and SGR) onto rows of styled cells and writes them back. Both libraries are tested in `test/test_tui.pl`
- `app/tui.pl` — `swipl tui`: lists, runs and prints the examples (SWI-Prolog finds a pack's `app/` scripts). The list is `examples/*.pl` less `*_lib.pl`, titled by each module's `<module>` line
- `test/test_tui.pl` — plunit tests
- `tools/` — development tools, not part of the library: `tui_doc.pl` transcribes the alias comments into `prolog/tui.pl` (`tools/TUI_PLDOC.md`)
- `pack.pl` — pack metadata

## Commands

- **Run an example**: `swipl app/tui.pl run gallery` (`swipl tui run gallery` once installed; `examples`, `source NAME` too). It runs `swipl -p library=prolog examples/gallery.pl -- ARGS` in a child process, the `--` keeping swipl from loading a `.pl` argument as code
- **Run the atto editor**: `swipl app/tui.pl run atto FILE`
- **Run the ink editor**: `swipl app/tui.pl run ink FILE`
- **Verify an example loads**: `swipl -p library=prolog -g "list_undefined, halt" examples/gallery.pl` (`-g` goals run before the example's main)
- **Painting benchmark** (needs a real terminal): `swipl -p library=prolog bench/paint.pl [FRAMES]` — how long the terminal takes to draw prepared runs, synced with a device-attributes round trip
- **Pipeline benchmark** (runs anywhere): `swipl -p library=prolog bench/pipeline.pl [REPEATS]` — per-stage cost of turning a view into runs
- **Reload code**: `make.` in a running SWI-Prolog session
- **Tag a release**: `swipl tag_release.pl [--sign]` — `version/1` in `pack.pl` is the single source of truth. Shows the published version (pack server), the newest `V*` tag and the local version, asks, then tags HEAD `V<version>` and pushes the tag to the remote matching `download/1`. Refuses unless the local version is newer than both, and the tracked files are committed. Then `swipl pack publish URL`
- **Run tests**: `swipl -p library=prolog -g "consult('test/test_tui.pl'), run_tests" -t halt`

## Architecture

### Module Boundaries

The guiding rule (from "Out of the Tar Pit"): a module implements what it is for, and does not know *why* it is called. A module that knows about its callers carries accidental complexity. The `tui:` prefix on the hooks is the package namespace, not such a coupling.

Every file that adds clauses to `tui:alias_drawable/2` or `tui:at_event_is/3` must declare them `:- multifile` itself. Otherwise a later-loaded file silently replaces its clauses.

### Event Loop (loop.pl)

Everything runs in the main thread, which owns the TTY (`wait_for_input/3` on `user_input` only works there). Each pass of `app_loop/4`:

1. Paints the current frame if it is not already on the substrate (and the size is known)
2. Asks the substrate for events, which blocks
3. Folds them through bubbling and the user's `update/3`; the app exits on `result(R)` from either

The app's view and update are called as by `once/1`. A failure raises `tui_callback_failed(update(Event) | view, State)` (after the substrate is restored), so an app's bug is never a silent exit.

The `app/5` options `reload(Key)` and `redraw(Key)` are handled in `app_event_state_display_next/5` before any bubbling; the key reaches neither components nor update. Redraw clears the substrate (display stale, no runs). Reload runs `make/0`, marks the frame stale but keeps the runs (so the new view is painted as a diff), then updates with `reloaded`. Without marking it stale, the unchanged state would keep the frame painted with the old code.

**The cursor.** Update may bind the state's cursor `X-Y`, or leave it unbound. The view may draw `cursor(Drawable)` (an alias defined in `loop.pl`), which places the cursor on the top-left cell drawn by it; because the view runs after update, this overrides any cursor update bound. If several are drawn, the top-left cell of them all wins. With neither, there is no cursor: nothing is highlighted, and events bubble through an empty stack (so only `at_event_is([], ...)` sees them) and arrows do not move anything. Arrow keys not claimed by a component move the cursor by default (the loop binds the new position). Update receives the state with the cursor as shown.

A frame is `frame(Commands, EventAssoc, Extent, Cursor, Images)`, computed from a state; `Cursor` is the resolved cursor or `none`; `Images` are the `image/3` terms with a cell on screen. It is tracked as `stale`, `fresh(F)` (computed, not painted) or `painted(F)`. Each event in a batch is routed through the frame of the state it applies to, but only the last frame is painted.

The loop's display is `display(Substrate, Tracked, Size, Runs, Images)`. Size is `unknown` until the first `terminal_size(Cols, Rows)` event, which (like any size change) clears the substrate. Runs are what is on the substrate; painting draws only the runs that changed. Images are those sent to the substrate; painting first sends the uploads and placements the frame's images need (`images_sent_actions/4`). A clear forgets both.

### Substrates (substrate.pl)

A substrate is a term passed through the loop, never global: `terminal`, or `vcr(Script)`. `substrate.pl` branches on it for session setup, events, clearing, and painting runs.

The terminal substrate (`terminal(Detected, Pending, Mouse)`, from `terminal_substrate(Options, S)`, built by `app/5` from its options unless `substrate(S)` is given) owns raw mode and SIGWINCH. The size comes from the OS (`tty_size/2`): at session start and from the SIGWINCH handler it is posted to the wake as `terminal_size(Cols, Rows)`.

Input: the substrate reads available codes and decodes them with `input.pl`. Codes of an incomplete escape sequence stay in `Pending`; while any are pending it waits at most 10 ms (the escape grace period) before decoding them as they are, so a lone ESC becomes `escape`. End of input is the event `eos`.

Keys: plain keys are atoms (`a`, `'A'`, `up`, `return`, `f5`); modified keys are `Mods+Key` with modifiers in the order ctrl, alt, shift, super, hyper, meta, e.g. `ctrl+shift+up`. Letters with modifiers are lowercase. Unrecognised sequences arrive as `unknown_input(Codes)`.

Stderr: for the session, `user_error` is rebound to a stream from `open_prolog_stream/4` (line buffered), whose callback posts `stderr(Text)` to the wake from whichever thread wrote; it is restored first in the cleanup, which posts what was still buffered. Not a pipe, which could fill and deadlock the main thread writing to it. The VCR substrate does not capture.

Bracketed paste is always on: a paste arrives as one `paste(Text)` event (a string, line breaks normalised to `"\n"`), never as keystrokes. An open paste is exempt from the escape grace period and waits for its end marker.

Mouse reporting is opt-in (`app/5` option `mouse(true)`): modes 1000, 1002 and 1006 on at session start, off at cleanup. SGR reports, and X10 reports from terminals without SGR, decode to `(X-Y)-mouse(Action, Button)` or `(X-Y)-mouse(scroll, Dir)`, possibly under modifiers. The loop bubbles a mouse event at X-Y instead of the cursor; a press first moves the cursor there (if there is one), like `moved(Dir)` the cursor moves regardless of what the press becomes; a mouse event no component rewrote reaches update with its position.

Kitty keyboard protocol: at session start the substrate queries for it, then requests device attributes. A Kitty reply before the device-attributes reply means support, and the substrate enables flag 1 (disambiguate); otherwise `Keyboard` becomes `legacy`. A Kitty graphics query is sent too; an `OK` reply (`kitty_graphics(Reply)`, decoded from an APC) means images can be shown. The device-attributes reply ends detection and is passed on as `terminal_properties([program(P), extended_keys(B), graphics(G)])` (P from `TERM_PROGRAM`, or `unknown`; list order not guaranteed), so apps can work around a terminal's limits. The substrate's detection state is `Keyboard-Graphics`. The decoder accepts both encodings at all times. Replies are consumed by the substrate. Clearing uses erase-display, not a full reset, so the keyboard mode survives resizes.

**Wake** (`wake.pl`): a `wake(Queue, In, Out)` term. Posting queues an event, then writes a byte to a pipe the loop waits on alongside `user_input`. Bytes are consumed before the queue is drained, so no event is stranded.

**Ports and subscriptions** (`subscriptions.pl`): the app's port is `port(Wake)`; `port_send/2` (exported by `library(tui)`) posts to it from any thread, and does nothing once the app has ended. There is no global "current app". The `app/5` option `subscriptions(Goal)` gives `call(Goal, State, Subs)`, called at the top of each loop pass. Subs are `every(Ms, Event)` and `thread(ThreadGoal)` (`call(ThreadGoal, Port)` in a detached thread; ending by itself posts `thread_ended(ThreadGoal, Status)`), identified by their term (compared as variants): the loop starts new ones and stops removed ones by signalling `throw(tui_stop)`, without joining, so a thread blocked in foreign code cannot hang the UI. The running set lives in a mutable term (`nb_setarg`) so that the app's cleanup stops them however it ends. The VCR's `receive(N)` waits for N posted events, so subscriptions are testable headless.

### Headless Testing (vcr.pl)

`app(State, View, Update, Result, [substrate(vcr(Script))])` runs an app against a script of `send(Events)`, `receive(N)` (the next N events posted by subscriptions), `expect(clear)`, `expect(graphics(Actions))` and `expect(runs(Runs))` (unbound Runs: any paint), consumed in order. Any divergence throws `vcr_mismatch(Expected, Actual)`. An exhausted script answers every request for events with `[eos]`; the app decides what that means (test apps typically return `result(...)`). A script starts with `send([terminal_size(Cols, Rows)])` followed by `expect(clear)`. See the `vcr` unit in `test/test_tui.pl`.

The terminal substrate needs a real TTY, so it can only be checked by running an app by hand; use the VCR for headless tests.

### Drawable System (drawable.pl)

Drawables are a term-based DSL rendered via the DCG `drawable//5`. Key drawable terms:

- **Primitives**: atoms/strings render as characters; `chars(List)`, `literal(Term)`
- **Layout operators** (custom ops, precedence 601):
  - `.>` — horizontal concat (left then right)
  - `.<` — horizontal concat, right-aligned first
  - `.\/` — vertical concat (top then bottom)
  - `./\` — vertical concat, bottom-aligned first
- **Combinators**: `translate(DX-DY, D)`, `port(W-H, D)`, `style(Attrs, D)`, `X-Y-D` (shorthand for translate), `zone(W-H, D)` (extent W×H regardless of D; no clipping), `align(Dir, D)` (placed against the edges of the zone it is directly in, or in that zone's list; elsewhere just D). The loop draws the view as `zone(Cols-Rows, View)`, so the frame's extent, and the cursor's range, is the terminal. Aligns are measured once with `drawable_raw`; `table/2` measures each cell once and places it as an already-aligned zone, merging the borders of per-cell boxes with `corners_unified/2`.
- **Core drawables**: `row/1`, `column/1`, `wrapped(Width, Chars)`, `clear(W-H)`, `line(Char, From, To)`, `box(W-H, Chars)` (Chars is `box_chars(H, V, TL, TR, BL, BR)` or `thin`/`thick`/`double`), `hover(Style, D)`, `cursor(D)`, `highlight(D)`. `cursor/1` and `highlight/1` are identity aliases: what they mean is found in the cells' alias stacks (the loop places the cursor, `render.pl` highlights the cursor's cell and the cells drawn by `highlight/1`, once however many apply), not in their attributes
- **Tagging**: `Key : Drawable` — annotates a drawable with a tag for event routing (see below)

Expansion produces a flat list of `(X-Y)-(Stack-Attrs-Char)` commands, deduplicated (last wins). Each command's Attrs holds one list per style, innermost first; `render.pl` applies them outermost first, so the innermost wins. It resolves each cell (hover, `char/1`, cursor highlight) and groups cells into runs `(X-Y)-(Attrs-Chars)`.

### Component System via alias_drawable/2

Custom components are defined as multifile `tui:alias_drawable(Term, Drawable)` clauses. During rendering, the alias stack tracks which components produced each character at each coordinate.

Event rewriting uses multifile `tui:at_event_is(AliasOrStack, X-Y-RawEvent, RewrittenEvent)` — components intercept and transform events before they bubble up. This is how checkboxes turn `' '` into `check_box-true/false`, scrollables turn Shift+arrows into scroll offsets, and moveables capture direction events.

Stack entries are `Origin-Alias`, Origin being the offset the alias was drawn at (the `raw` clause shifts the origins of embedded commands). `stack_event_is/3` (`events.pl`) takes the absolute `X-Y-Event` and gives each component the event relative to its origin, so an input knows where in it the cursor is. Under a scroll, relative positions are content positions. `[]` sees the absolute position, or the bare event when there is no cursor.

Bubbling is nondeterministic: `at_event_is/3` may have several solutions (`*->`), each bubbling on from the same component. The loop collects them all (`findall`) and folds them in order: a direction moves the cursor one cell, `cursor_by(DX-DY)` moves it by an offset (bubbling nothing), `noop` is dropped (a component taking an event to do nothing; it also stops bubbling there), anything else goes to update, and `result(R)` stops. All are routed through the frame the raw event arrived at. A cursor movement bubbles `moved(Dir)` from the old position and, for an arrow key no component claimed, `arrived(Dir)` at the new one; the cursor moves regardless, and whatever they become (other than themselves) is handled with the cursor moved. Directions produced by components bubble no `arrived(Dir)`, because their frame may predate the update they follow. So a component can answer a key with a new value and `cursor_by` to keep the cursor after the edit, and keep the cursor on cells it accepts by answering `arrived(Dir)` (or a mouse press) with `cursor_by` (as `input/3` does).

### Tagging with `Key : Drawable`

The `:` operator attaches an identity tag to a drawable for event routing. Rendering ignores the tag. During event bubbling, when a component event `ComponentName-Value` passes through a `Key:Component` node and `ComponentName` matches the functor of `Component`, the event is rewritten to `Key-Value`. Raw events (atoms like `up`, `down`) and events from deeper nested components pass through unmodified.

```prolog
% Tag a scroll component instance with its model key:
scroll(Id) : scroll(20-15, Offset, Content)
% scroll fires scroll-(0-5), tag rewrites to scroll(Id)-(0-5)
```

This replaces the earlier `id/N` mechanism which relied on `=..`.

### State Shape

App state is `(CursorX-CursorY)-Model` where Model is user-defined (typically an assoc list from `assocs.pl`).

### assocs.pl

Lightweight association list library using plain `Key-Value` pair lists (not `library(assoc)` AVL trees). Supports pattern-matching extraction via `assocs_pairs/2` and update via `pair_pair_assocs_assocs/4`.

### components.pl

Ready-made, styled components, opt-in via `library(tui/components)`: `check_box/2`, `button/1`, `input/3`, `rule/1`, `frame/2-3`, `titled_frame/3-4`, `scroll/3`. Components here make styling choices; building blocks without them belong in `drawable.pl`. Their visual design is `QUIET_GRID.md`. Agreed conventions for this module: focus (the cursor on an interactive component) is shown `negative`, via `hover/3`, and only focus toggles negative; faint standing alone means disabled, and beside non-faint text marks secondary importance; set and unset are told apart by shape (`[x]`, `[ ]`, `[-]`), never by an attribute; buttons look like `┃OK┃`, and `▌OK▐` focused (glyph swap with `char/1`); buttons and check boxes hide the cursor (`cursor_hidden`), and left and right leave them in one keypress; frames are rules above and below, with no side walls; Space and Return activate; components emit `Name-Value` events; Shift+arrows drag what is under the cursor in the arrow's direction, as with a mouse (in a scroll area the content, on a scrollbar the thumb), leaving plain arrows to the cursor. With the mouse: a left press activates as Space does, and the wheel scrolls.

### TODO.md and CONSIDERATIONS.md

`TODO.md` lists open work. `CONSIDERATIONS.md` holds design notes and analysis (the Kitty graphics design, caching experiments, etc.).

Design notes and analysis for future features (Kitty graphics protocol, caching experiments, etc.).

## Style Guidelines

See `PROLOG_STYLE.md` for full conventions. Key points:

- **Relational naming**: functor describes the relation, not an action (`list_deduped/2` not `remove_duplicates/2`). One word per argument; double underscore `__` for multi-word argument phrases.
- **Section markers**: use quoted facts like `'#section_name'.` to organize predicates within a file
- **Purity**: pure core, impure shell. Mark impurity with `% IMPURE:` comments
- **Arithmetic**: CLP(FD) by default; `is/2` only when provably ground and marked `% IMPURE:`
- **Branching**: `if_/3` with reified tests preferred; `-> ;` only for ground dispatch
- **Formatting**: 4-space indentation, no blank lines between clauses of same predicate, one blank line between predicates
- **Documentation**: PLdoc with `%!` (preferred) and mode markers (`+`, `-`, `?`) plus `is det/semidet/nondet`. Every file has a `/** <module>` comment and every exported predicate a structured comment; mode-line arguments are plain variables (`+Size`, then "Size being W-H" in the text), and different arities get separate comments. Comments on non-exported helpers are plain `%`. The `doc` test unit runs `test/doc_check.pl` (standalone: `swipl -p library=prolog test/doc_check.pl`), which fails on any of this, and on any warning while loading
- **Aliases** (`tui:alias_drawable/2` clauses) have a documentation format of their own, not `%!` comments: read `tools/TUI_PLDOC.md` before writing or changing one
- **Modules**: one per file, explicit exports, ≤200 clauses
