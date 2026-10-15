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


## Rendering vs Painting Costs (October 2026)

Two benchmarks separate what the terminal costs from what tui costs:

- `bench/paint.pl` (needs a real terminal) paints prepared runs through the terminal substrate. A write returns once the OS has the bytes, so it syncs by requesting device attributes and waiting for the reply, which comes only after all earlier output is processed. *stream* is throughput (many frames, one sync); *synced* is per-frame latency.
- `bench/pipeline.pl` (runs anywhere) times each stage of turning a view into runs.

### Painting (80x24, 100 frames)

| terminal | scenario | runs | stream ms | synced ms | worst ms |
|---|---|---|---|---|---|
| kitty | full_plain | 24 | 0.052 | 1.132 | 1.585 |
| kitty | full_styled | 1920 | 7.608 | 8.612 | 36.047 |
| kitty | row | 1 | 0.011 | 1.149 | 1.254 |
| kitty | cell | 1 | 0.011 | 1.154 | 1.644 |
| iTerm2 | full_plain | 24 | 0.224 | 34.856 | 37.417 |
| iTerm2 | full_styled | 1920 | 8.012 | 34.602 | 44.667 |
| iTerm2 | row | 1 | 0.351 | 22.835 | 37.027 |
| iTerm2 | cell | 1 | 0.169 | 22.403 | 34.862 |

tmux added almost no overhead (not tabulated).

- kitty draws a full screen in about 1 ms; painting is effectively free.
- iTerm2 has a latency floor of 22-35 ms regardless of content: a single cell costs the same as a full screen. That is its response cadence, not drawing cost, and nothing on our side affects it.
- full_styled streams at ~8 ms in both terminals, against 0.05 ms for full_plain: the cost is ours, `ansi_format/3` called once per run (~4 µs each). It matters only on screens with many style changes. Fix if needed: encode a frame's escape sequences ourselves and write once.

### Pipeline: replacing predsort (120x40, ms, median of 5, back to back)

`keylist_deduped_prioritize_last/2` and run grouping used `predsort/3`, which calls a Prolog comparator per comparison. Dedupe now reverses and uses `sort(1, @<, ...)` (keeps the first of equal keys, i.e. the last drawn); render keys cells `Y-X` and uses `keysort/2`. Output identical.

| scene | dedupe before → after | runs before → after | total before → after |
|---|---|---|---|
| text | 5.51 → 0.64 | 9.14 → 2.38 | 18.41 → 7.03 |
| styled | 5.83 → 0.62 | 10.68 → 4.64 | 23.01 → 12.09 |
| demo | 3.61 → 0.44 | 4.61 → 2.02 | 16.78 → 12.02 |
| atto, 100 lines | 8.39 → 0.85 | 9.82 → 3.37 | 36.79 → 23.17 |
| atto, 2000 lines | 8.22 → 0.89 | 9.63 → 3.39 | 257.91 → 244.25 |

Absolute times vary between sessions (a whole run can be ~2x faster or slower); compare within one back-to-back run.

### Conclusions

- On kitty, tui's own logic dominates: ~7-23 ms per full 120x40 frame after the sort fix, versus ~1 ms to paint.
- Expansion (drawables into commands) is now most of the remaining cost: 237 of 244 ms for atto with 2000 lines. The port clips after the whole document is expanded, so every line is expanded on every frame. Candidates: `memoize(Drawable)` (opt-in, keyed on ground drawables), and atto drawing only lines that can be visible.
