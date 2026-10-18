# Considerations

Design notes and architectural analysis for future features.

## Kitty Terminal Graphics Protocol (implemented)

Reference: https://sw.kovidgoyal.net/kitty/graphics-protocol/

Implemented as `image(Id, Source, W-H)` (`prolog/tui/image.pl`). The design, and why:

### Placement: Unicode placeholders, not direct placement

Kitty can place an image at the cursor (`a=p`), or show it through placeholder characters (`U=1`, Kitty 0.28+, also Ghostty). Directly placed images live on their own layer: text drawn over them does not remove them, so every move or removal needs an explicit delete, and a second diff of placements beside the runs.

With placeholders, each cell of an image is an ordinary command: U+10EEEE plus two diacritics (row, column, indices into Kitty's table of 297), with the image id as the 24-bit foreground colour, `fg(R,G,B)`. Diffing, erasing, clipping by ports, zones and layering all work unchanged; drawing over a cell replaces that piece of the image. The command format did not change; a `Char` may now be several codepoints (still one cell), which `ansi_run/1` writes by concatenating. Every cell carries both diacritics (Kitty can infer them from the previous cell), because a repainted run may start partway through an image.

### Uploads: declared by the view, diffed like runs

The image alias is on its cells' stacks, as `cursor(_)` is. The loop collects the frame's images from the on-screen placeholder cells (distinct ids only: `findall/3` would copy the Source once per cell) and `images_sent_actions/4` compares them with what the display records as sent: a new image is `transmit` then `place`; a new size of one already sent is `place` only (placement id 1 is reused, so it replaces). The substrate sends actions before the frame's runs. Nothing is sent twice, the core stays pure, and the VCR checks them as `expect(graphics(Actions))`. Images no longer drawn are kept by the terminal (drawing them again sends nothing); a clear (resize) forgets what was sent, in case clearing deletes them, and they are re-sent. The full reset at session end removes them.

Sources: `png(Bytes)`, `rgba(PW-PH, Bytes)`, `rgb(PW-PH, Bytes)` (raw pixels need their pixel size), `file(Path)` (the terminal reads it; local terminals only). Bytes are octets; base64 and 4096-byte chunking are done by `terminal.pl`. All commands carry `q=2`, so the terminal does not reply.

### Detection

At session start the substrate sends a graphics query (`a=q`) before the device-attributes request. An `OK` reply, decoded from the APC `ESC _ G … ESC \` as `kitty_graphics(Reply)`, sets `graphics(true)` in `terminal_properties/1`. The substrate sends what the view draws regardless; apps draw images only once they see `graphics(true)`, since elsewhere placeholders show as unknown characters.

### Open

- Untested on a real terminal so far (only through the VCR and escape tests).
- The cursor on an image cell adds `negative`; how Kitty renders a reversed placeholder is unverified.
- Legacy `alt+_` (`ESC _`) now starts an APC; alone it is resolved by the escape grace period, but followed within 10 ms by more keys it becomes `unknown_input`.
- `base64/2` is written in Prolog; large images take noticeable time to encode, once per upload.
- One placement per image id: the same image at two sizes at once needs two ids.
- Collecting images costs every app a pass over the frame's commands (~0.3 ms for 5000 cells). Placeholder atoms start with U+10EEEE, so one `@>` comparison per cell rules out ordinary characters; searching every stack with `memberchk/2` instead cost 1.5–1.8 ms in scenes with deep stacks.


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


## memoize(Drawable) (Attempted, Reverted)

### Idea

An opt-in `memoize(D)` drawable: the developer marks subtrees worth caching, which avoids the failure of the earlier blanket alias caching (cheap aliases paying for the cache). `D` must be ground. Its expansion at 0-0 is cached and replayed through `raw(...)` embedding, which already translates cells and appends the outer stack and attributes. Because a drawable's output depends only on the drawable, the cache only ever affects speed.

### Design

- Key: `term_hash(D, H)`, checked with `==` against the stored `D`. Non-ground `D` is drawn without the cache.
- Value: the cells and `D`'s own extent. The extent must be stored, not derived from the cells: `port(10-3, "a")` has a 10x3 extent but one cell, and layout (`.>`, `.\/`) depends on extents.
- Lifetime: entries tagged with the last frame (generation) that used them; a hit updates only the tag, entries unused in the current or previous frame are dropped. `drawable__normalized_commands__end/3` advanced the generation, so the loop knew nothing of it.
- On a hit, the cells are `copy_term`ed: they may hold variables that drawing binds (a hover's group variable, bound by `apply_focus/2`), and the stored copy must stay unbound.

### Result

atto lines were wrapped in `memoize`. Expansion time on the pipeline benchmark (120x40, ms):

| store | atto, 100 lines off / cold / warm | atto, 2000 lines off / cold / warm |
|---|---|---|
| clauses (`assertz`/`clause`) | 17 / 242 / 115 | 209 / 5940 / out of memory (1 GB stack) |
| global variables (`nb_setval`/`nb_current`) | 16.5 / 25.4 / 17.0 | 248 / 467 / 278 |

*cold*: cache cleared before every expansion; *warm*: filled by the previous expansion, as in normal editing.

### Why

1. **Clauses lose sharing.** Each cell's stack holds the alias terms that drew it (`numbered_line(N, G, W, Chars, Col)`, `wrapped(W, Shown)`), each containing the whole line, all shared in memory. Compiling a term into a clause and retrieving it rebuilds it without sharing, so every cell got its own copy of its line: cells x line length. Measured on a 32 KB shared term, retrieval cost: clause 24 MB, `recorded/2` 48 KB (sharing kept, but copied), `nb_getval/2` 24 bytes (a reference, no copy), `copy_term/2` 32 bytes (ground subterms are shared).
2. **Even without copying, replaying costs as much as drawing.** An atto line's expansion is almost all per-cell work (`chars(...)` emits one command per character and little else), and replaying cached cells is also per-cell work (raw embedding translates each cell and appends stacks and attributes). Add the hash, the `==` check and `copy_term`, and a hit costs about what a redraw does. memoize pays only for drawables that do much work per cell produced (layout calculations, deep alias nesting, formatting).

### Not pursued: clip-aware expansion

The cached extent would let an off-screen `memoize(D)` emit nothing and cost one lookup, with layout still correct, turning `memoize` + `port` into a virtualized scroll view. It needs the clip rectangle passed down the drawable DCG (`drawable//5` becomes `drawable//6`, and `port` narrows the clip instead of filtering afterwards). Not worth the architectural change: an app that needs it (an editor with large files) knows its line sizes and draws only what is visible, which is simpler and faster. atto already scrolls its own source at vim speed.

### What atto did instead

atto's view draws only the lines with a row on screen. It skips the lines entirely above the top visible row (summing their row counts, `Len // Width + 1`), takes lines until one starts below the last visible row, and puts those in the column, offset by the first one's starting row minus the top row. The port still clips, so a line only partly visible at either edge is drawn whole and cut. Row counts are computed each frame rather than tracked in the model: `length/2` is linear (it walks the list), but for 2000 lines and 266k characters all row counts take ~1.6 ms, and only lines above the view are counted.

A first version kept every line in the column and drew off-screen lines as `translate(0-(Rows-1), [])`, an empty drawable exactly `Rows` tall. It worked (a 20k-line file went from unworkable to usable), but still expanded one alias per line per frame.

Pipeline benchmark, 120x40, ms (median of 5; each row back to back with the one before it):

| atto, 2000 lines | view | expand | total |
|---|---|---|---|
| every line drawn | 0.38 | 426.92 | 439.23 |
| off-screen lines as empty placeholders | 2.11 | 17.08 | 31.31 |
| placeholders (rerun) → visible lines only | 1.18 → 0.06 | 9.77 → 8.00 | 17.73 → 14.83 |

Screens are identical across all three. The benchmark's cursor is at the top of the file; near the end, skipping the lines above the view costs a few ms at 20k lines.

### Also learned

`findall/3` copies each solution and loses sharing in the same way. Several components (`clear/1`, `line/3`) build cell lists with it; harmless at their sizes, but worth knowing.
