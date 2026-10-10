# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A Text User Interface (TUI) framework for SWI-Prolog, inspired by TEA (The Elm Architecture). Apps are defined with `app/4` accepting a model, view callback, update callback, and final-result argument.

## Pack Structure

This is a SWI-Prolog pack. Library modules live in `prolog/`, internal modules in `prolog/tui/`.

- `prolog/tui.pl` — public module `tui` (auto-loads components)
- `prolog/tui/components.pl` — module `tui_components`
- `prolog/tui/assocs.pl` — module `tui_assocs`
- `prolog/tui/utils.pl` — module `tui_utils`
- `examples/demo.pl` — example app
- `pack.pl` — pack metadata

## Commands

- **Run the example app**: `swipl -p library=prolog -g go examples/demo.pl`
- **Verify modules load**: `swipl -p library=prolog -g halt examples/demo.pl`
- **Reload code**: `make.` in a running SWI-Prolog session
- **Run tests**: `swipl -p library=prolog -g "consult('test/test_tui.pl'), run_tests" -t halt`

## Architecture

### Event Loop

Everything runs in the main thread, which owns the TTY (`wait_for_input/3` on `user_input` only works there). Each pass of `app_loop/4`:

1. Paints the current frame if it is not already on screen
2. Blocks in `wait_for_input([user_input, WakeIn], ...)`
3. Collects every ready event — posted events first, then all available keystrokes
4. Folds them through bubbling and the user's `update/3`; the app exits on `result(R)` from either

A frame is `frame(Commands, EventAssoc, Extent)`, computed from a state. It is tracked as `stale`, `fresh(F)` (computed, not painted) or `painted(F)`. Each event in a batch is routed through the frame of the state it applies to, but only the last frame is painted.

**Wake pipe** (`'#wake'`): other threads call `post(Event)` (not yet exported), which queues the event on a message queue and then writes a byte to a pipe the loop waits on. The loop consumes the bytes before draining the queue, so no event is stranded. SIGWINCH only posts `terminal_resized`; the loop issues the size request, and the reply arrives as a `terminal_size(Cols, Rows)` input.

### Drawable System (tui.pl)

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

Rendering produces a flat list of `(X-Y)-(Stack-Attrs-Char)` commands, deduplicated (last wins).

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

Reusable components: `Key:Drawable` (tagging), `column/1`, `row/1`, `check_box/2`, `input/3`, `frame/2-3`, `titled_frame/3-4`, `scroll/3`.

### Profiling

Set `TUI_PROFILE=1` to display drawable expansion time (milliseconds) in the top-left corner. Typical render times for the example app: 6-25ms.

### CONSIDERATIONS.md

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
