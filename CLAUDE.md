# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A Text User Interface (TUI) framework for SWI-Prolog, inspired by TEA (The Elm Architecture). Apps are defined with `app/4` accepting a model, view callback, update callback, and final-result argument.

## Pack Structure

This is a SWI-Prolog pack. Library modules live in `prolog/`, internal modules in `prolog/tui/`.

- `prolog/tui.pl` — public module `tui`: a facade of operators, re-exports, and the hook declarations (auto-loads components)
- `prolog/tui/utils.pl` — `tui_utils`: debug helpers (`log/1`, `?`, `@`), list/DCG helpers, direction and limits geometry. Depends on nothing.
- `prolog/tui/terminal.pl` — `tui_terminal`: generic ANSI output (`ansi_*`, `ansi_run/1`), device-attributes and Kitty keyboard queries
- `prolog/tui/input.pl` — `tui_input`: decodes terminal input codes into events (legacy xterm and Kitty keyboard protocol), with no side effects
- `prolog/tui/drawable.pl` — `tui_drawable`: the drawable DSL (`drawable//5`), attributes, commands, cell resolution (conceal/reveal)
- `prolog/tui/hover.pl` — `tui_hover`: the `hover/2` component and cursor-dependent hover styling
- `prolog/tui/events.pl` — `tui_events`: event bubbling through component stacks, the event map
- `prolog/tui/render.pl` — `tui_render`: commands → runs, and which runs changed (no side effects)
- `prolog/tui/wake.pl` — `tui_wake`: a message queue that `wait_for_input/3` can wait on
- `prolog/tui/substrate.pl` — `tui_substrate`: what the loop draws onto and gets events from (`terminal` or `vcr(Script)`)
- `prolog/tui/vcr.pl` — `tui_vcr`: scripted replay for headless tests
- `prolog/tui/loop.pl` — `tui_loop`: `app/4`, `app/5` and the event loop
- `prolog/tui/components.pl` — `tui_components`: reusable components, including `box/2`, `clear/1`, `line/3`
- `prolog/tui/assocs.pl` — `tui_assocs`
- `examples/demo.pl` — example app
- `test/test_tui.pl` — plunit tests
- `pack.pl` — pack metadata

## Commands

- **Run the example app**: `swipl -p library=prolog -g go examples/demo.pl`
- **Run the atto editor**: `swipl -p library=prolog examples/atto.pl -- FILE` (the `--` stops swipl from loading a `.pl` FILE as code)
- **Verify modules load**: `swipl -p library=prolog -g halt examples/demo.pl`
- **Reload code**: `make.` in a running SWI-Prolog session
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

**The cursor.** Update may bind the state's cursor `X-Y`, or leave it unbound. The view may draw `cursor(Drawable)` (an alias defined in `loop.pl`), which places the cursor on the top-left cell drawn by it; because the view runs after update, this overrides any cursor update bound. If several are drawn, the top-left cell of them all wins. With neither, there is no cursor: nothing is highlighted, and events bubble through an empty stack (so only `at_event_is([], ...)` sees them) and arrows do not move anything. Arrow keys not claimed by a component move the cursor by default (the loop binds the new position). Update receives the state with the cursor as shown.

A frame is `frame(Commands, EventAssoc, Extent, Cursor)`, computed from a state; `Cursor` is the resolved cursor or `none`. It is tracked as `stale`, `fresh(F)` (computed, not painted) or `painted(F)`. Each event in a batch is routed through the frame of the state it applies to, but only the last frame is painted.

The loop's display is `display(Substrate, Tracked, Size, Runs)`. Size is `unknown` until the first `terminal_size(Cols, Rows)` event, which (like any size change) clears the substrate. Runs are what is on the substrate; painting draws only the runs that changed.

### Substrates (substrate.pl)

A substrate is a term passed through the loop, never global: `terminal`, or `vcr(Script)`. `substrate.pl` branches on it for session setup, events, clearing, and painting runs.

The terminal substrate (`terminal(Keyboard, Pending)`, from `terminal_substrate/1`) owns raw mode and SIGWINCH. The size comes from the OS (`tty_size/2`): at session start and from the SIGWINCH handler it is posted to the wake as `terminal_size(Cols, Rows)`.

Input: the substrate reads available codes and decodes them with `input.pl`. Codes of an incomplete escape sequence stay in `Pending`; while any are pending it waits at most 10 ms (the escape grace period) before decoding them as they are, so a lone ESC becomes `escape`. End of input is the event `eos`.

Keys: plain keys are atoms (`a`, `'A'`, `up`, `return`, `f5`); modified keys are `Mods+Key` with modifiers in the order ctrl, alt, shift, super, hyper, meta, e.g. `ctrl+shift+up`. Letters with modifiers are lowercase. Unrecognised sequences arrive as `unknown_input(Codes)`.

Bracketed paste is always on: a paste arrives as one `paste(Text)` event (a string, line breaks normalised to `"\n"`), never as keystrokes. An open paste is exempt from the escape grace period and waits for its end marker.

Kitty keyboard protocol: at session start the substrate queries for it, then requests device attributes. A Kitty reply before the device-attributes reply means support, and the substrate enables flag 1 (disambiguate); otherwise `Keyboard` becomes `legacy`. The decoder accepts both encodings at all times. Replies are consumed by the substrate. Clearing uses erase-display, not a full reset, so the keyboard mode survives resizes.

**Wake** (`wake.pl`): a `wake(Queue, In, Out)` term. Posting queues an event, then writes a byte to a pipe the loop waits on alongside `user_input`. Bytes are consumed before the queue is drained, so no event is stranded. `post/1` in `loop.pl` (not yet exported) delivers to the running app.

### Headless Testing (vcr.pl)

`app(vcr(Script), State, View, Update, Result)` (from `library(tui/loop)`) runs an app against a script of `send(Events)`, `expect(clear)` and `expect(runs(Runs))`, consumed in order. Any divergence throws `vcr_mismatch(Expected, Actual)`. An exhausted script answers every request for events with `[eos]`; the app decides what that means (test apps typically return `result(...)`). A script starts with `send([terminal_size(Cols, Rows)])` followed by `expect(clear)`. See the `vcr` unit in `test/test_tui.pl`.

The sandbox has no PTY, so the terminal substrate can only be checked by running the demo by hand.

### Drawable System (drawable.pl)

Drawables are a term-based DSL rendered via the DCG `drawable//5`. Key drawable terms:

- **Primitives**: atoms/strings render as characters; `chars(List)`, `literal(Term)`
- **Layout operators** (custom ops, precedence 601):
  - `.>` — horizontal concat (left then right)
  - `.<` — horizontal concat, right-aligned first
  - `.\/` — vertical concat (top then bottom)
  - `./\` — vertical concat, bottom-aligned first
- **Combinators**: `translate(DX-DY, D)`, `port(W-H, D)`, `style(Attrs, D)`, `X-Y-D` (shorthand for translate)
- **Builtins**: `box(W-H, Style)`, `clear(W-H)`, `hover(Style, D)`
- **Tagging**: `Key : Drawable` — annotates a drawable with a tag for event routing (see below)

Expansion produces a flat list of `(X-Y)-(Stack-Attrs-Char)` commands, deduplicated (last wins). `render.pl` resolves each cell (hover, conceal, cursor highlight) and groups cells into runs `(X-Y)-(Attrs-Chars)`.

### Component System via alias_drawable/2

Custom components are defined as multifile `tui:alias_drawable(Term, Drawable)` clauses. During rendering, the alias stack tracks which components produced each character at each coordinate.

Event rewriting uses multifile `tui:at_event_is(AliasOrStack, RawEvent, RewrittenEvent)` — components intercept and transform events before they bubble up. This is how checkboxes turn `' '` into `check_box-true/false`, scrollables turn arrow keys into scroll offsets, and moveables capture direction events.

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

Reusable components: `box/2`, `clear/1`, `line/3`, `Key:Drawable` (tagging), `column/1`, `row/1`, `check_box/2`, `input/3`, `frame/2-3`, `titled_frame/3-4`, `scroll/3`.

### TODO.md and CONSIDERATIONS.md

`TODO.md` lists open work. `CONSIDERATIONS.md` holds design notes and analysis for future features (Kitty graphics protocol, caching experiments, etc.).

Design notes and analysis for future features (Kitty graphics protocol, caching experiments, etc.).

## Style Guidelines

See `PROLOG_STYLE.md` for full conventions. Key points:

- **Relational naming**: functor describes the relation, not an action (`list_deduped/2` not `remove_duplicates/2`). One word per argument; double underscore `__` for multi-word argument phrases.
- **Section markers**: use quoted facts like `'#section_name'.` to organize predicates within a file
- **Purity**: pure core, impure shell. Mark impurity with `% IMPURE:` comments
- **Arithmetic**: CLP(FD) by default; `is/2` only when provably ground and marked `% IMPURE:`
- **Branching**: `if_/3` with reified tests preferred; `-> ;` only for ground dispatch
- **Formatting**: 4-space indentation, no blank lines between clauses of same predicate, one blank line between predicates
- **Documentation**: PLdoc with `%!` (preferred) and mode markers (`+`, `-`, `?`) plus `is det/semidet/nondet`
- **Modules**: one per file, explicit exports, ≤200 clauses
