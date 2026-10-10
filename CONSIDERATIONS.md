# Considerations

Design notes and architectural analysis for future features.

## Kitty Terminal Graphics Protocol

Reference: https://sw.kovidgoyal.net/kitty/graphics-protocol/

Nothing fundamental prevents supporting the Kitty graphics protocol. The architecture is compatible.

The key question is whether the drawable system's `(X-Y)-(Stack-Attrs-Char)` command model can accommodate graphics.

### What works already

- Images are placed at cursor positions (character cell coordinates) — the drawable system already tracks X-Y positions
- Images are sent via escape sequences to the TTY — the event loop is the single writer to the terminal
- Placement is a write-and-forget operation, just like writing a character

### What doesn't conflict but needs extension

- A drawable like `image(Id, W-H)` would need to emit something other than single-character commands. The rendering pipeline assumes `(X-Y)-(Stack-Attrs-Char)` where Char is a single-character atom. An image placement is an escape sequence, not a character. Options:
  - Reserve the cell space (emit placeholder chars) and send the graphics escape separately
  - Extend the command format to allow a graphics variant alongside character commands
- The `location_style_char` cache avoids redundant writes by remembering what's at each cell. An analogous cache for image placements would be needed — don't re-transmit an image that's already displayed at that position
- Image data needs to be transmitted once (uploaded to terminal memory with an ID), then placed many times. That's a two-phase operation: upload in `tui_init` or lazily on first use, place during render. The paint step (`tty_render/2`) is the natural place for both

### What's irrelevant to the architecture

- Base64 encoding — SWI-Prolog has `library(base64)`
- Chunked transmission — just a loop in the output thread
- Z-index layering — the Kitty protocol handles this, just pass the parameter
- Bidirectional responses — nice-to-have for error checking but not required for basic display

### The one real design question

Images span multiple cells (e.g., 20x10), but the drawable system works cell-by-cell. An `image` drawable would need to claim a rectangular region. The `port(W-H, ...)` and `clear(W-H)` components already deal with rectangular regions, so there's precedent. The image drawable would emit its escape sequence at the top-left cell and emit space placeholders for the remaining cells.

Architecturally clear, no blockers. It's an extension to the command format and a new component type, not a rethink.


## alias_drawable Caching (Attempted, Reverted)

### Idea

Since `alias_drawable/2` is pure (assuming first-solution-only semantics), results can be memoized. An even/odd generational cache (`asserta`-based) would retain results from the previous render and promote cache hits into the current generation, discarding entries older than one render.

### What was tried

- `cached_alias(Gen, Term, Expanded)` dynamic predicate with `asserta` for fast first-argument indexing
- `flip_generation` called at the start of each render to rotate generations and discard stale entries
- `alias_drawable_cached/2` wrapping the lookup: check current gen, then previous gen (promote on hit), then compute fresh
- `copy_term/2` on retrieval to handle terms with free variables (e.g., `hover/2`'s unbound hover group flag)

### Result

Render times increased from 6-25ms to 40-60ms. The overhead of `copy_term/2`, `asserta`, dynamic predicate lookup, and generational bookkeeping exceeded the cost of simply recomputing alias expansions. The example app's alias_drawable clauses are cheap pattern matches and list operations — caching added overhead to the fast path without reducing work on the slow path.

### Conclusion

Not worth it at current scale. SWI-Prolog's tabling system also doesn't fit because it has no generational expiry. If alias_drawable expansions become expensive in the future (e.g., layout calculations, image loading), revisit with:

- Selective caching: only cache expansions that exceed a cost threshold
- Avoiding `copy_term`: refactor `hover/2` to eliminate free variables in expansions, removing the main source of overhead
- Coarser caching: cache the entire `drawable__normalized_commands__end` result keyed on the full model, not individual alias expansions
