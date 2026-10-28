# Quiet Grid: TUI visual spec (v3)

This spec defines the visual design for the ready-made components of `library(tui/components)`. It uses five SGR attributes and a small set of Unicode glyphs. Frames have no side walls, and color is optional. Because the design is monochrome, it works in any terminal theme.

Scope: visual design only. Behaviour such as scroll math and key handling is defined elsewhere.

**v3 amendments** fit v2 to the framework:

- The attribute names are the framework's: `negative` (inverse) and `faint` (dim).
- The cursor is not drawn by components. The framework shows it by *highlighting* its cell (section 3).
- Unicode is the only glyph tier.
- Frames keep their size but lose their side walls.
- Faint standing alone means disabled; with non-faint text or components, it indicates secondary importance.

Open points are listed in section 10.

## 1. Principles

1. **Structure.** Whitespace and rules give the layout its structure. Frames are drawn as rules above and below, never as side walls.
2. **Reserved attributes.** Faint text standing alone reads as disabled. Faint text visibly paired with text that is not faint, such as a shortcut beside its command's name in a menu, reads as secondary; when disabled, both are faint. Only an interactive component gaining or losing focus may toggle `negative`. A non-interactive component may draw `negative` where that is unambiguous, such as a progress fill, but never toggles it. Weight is otherwise `bold > normal`.
3. **Underline is structural.** It marks rules, the active tab, table headers and input fields. It never adds emphasis.
4. **Shape carries state.** Set and unset, checked and unchecked, are told apart by glyphs (`[x]` and `[ ]`), never by an attribute.
5. **Color is optional.** It can reinforce an existing encoding but must never be the only one.

## 2. Attributes

| Attribute | SGR | Used for |
|---|---|---|
| `bold` | `1` | emphasis, headers, active tab, key names, status markers |
| `faint` | `2` | Faint standing alone means disabled. Faint in conjunction with non-faint is used to indicate secondary importance. |
| `italic` | `3` | input placeholders, always with their angle brackets (which carry the state) |
| `underline` | `4` | rules (on spaces), frame borders, active tab, table header, input field |
| `negative` | `7` | focus: the interactive component under the cursor, as `hover([negative], …)`, the only toggled use; also fixed data fills where unambiguous (progress), never toggled |

`crossed_out` (`9`) is available, for example for removed lines in diffs. Other SGR extras, such as curly underlines, underline color and overline, are not supported by the framework.

**Hard rules**

- **Never combine bold and faint.** Both are reset by `22`, and terminals render the combination inconsistently. A disabled component draws itself faint, without bold. Note that blocked content, such as a modal backdrop, is rendered faint as a whole, and in such specific cases its bold becomes faint bold.
- **Never use faint as the only encoding of a state.** Some terminals ignore it, including the Linux text console. Pair it with a glyph, a position, or another attribute.
- **Negative toggles only with focus.** Only an interactive component may toggle `negative`, when it gains or loses focus. Focus is the component under the cursor. A non-interactive component may draw `negative` where its shape makes that unambiguous, such as a progress fill, but its `negative` never changes with its state.

## 3. Primitives

- **Rule:** a run of spaces drawn underlined. It reads as a seamless hairline along the baseline.
- **Block:** a run of spaces drawn negative. It gives solid cells, for fixed fills such as progress (section 2).
- **Glyph swap:** `char(C)` in a hover style draws `C` in place of each character drawn while the component has focus. Hovers sharing a group variable switch together, so parts of a component (a button's end caps) can change shape with its focus. `C` must be one column wide.
- **Highlight:** the framework's `highlight/1`, which is also how the cursor is shown. It adds `negative` to a cell, or removes it from a cell that has it. A negative space without underline on the default background would then be blank, so it is underlined instead. A cell is highlighted once, however many highlights (and the cursor) apply.
  - With the cursor on a rule or an empty input cell, the cell becomes a solid block.
  - With the cursor on a progress fill, it shows as a hole in the fill.

## 4. Layout

- **Spacing.** A cell is about twice as tall as it is wide, so horizontal padding is twice the vertical padding. The default gap is 2 columns or 1 row.
- **Region separators.** Separate regions with a blank row, a rule, or a frame.
- **Status line.** The bottom row holds state on the left and key hints on the right. It is never framed.

## 5. Components

Mockup notation used below: `{i:…}` negative, `{b:…}` bold, `{d:…}` faint, `{u:…}` underline, `{t:…}` italic. Flags combine, so `{bu:…}` is bold and underlined.

**Focus.** A component you activate (button, check box, list row, text input, scrollbar) shows focus as solid reverse video: what it draws becomes solid. That is not the same as negative. Usually negative does it, as `hover([negative], …)` over the whole component. But where a glyph is already half solid, as a scrollbar's thumb is, negating it only swaps which half is solid; such a component fills its glyphs instead, by glyph swap (section 3). In a component that shows the cursor (a text input), the cursor is the one normal-video cell (section 3). A focused component may also change glyphs for its shape, as a button's caps do.

Some interactive components are units (the framework's `unit/1`): though they cover many cells of the grid, the user experiences them as a single location. Any arrow key moves the cursor out of one in that direction, in one keypress. The cursor is hidden on a unit, because showing a position within it would contradict that experience; it still keeps its position, so that moves through units are consistent. Buttons, check boxes (the box with its label) and scrollbars are units. Text inputs are not, because the cursor marks the insertion point.

### Frame

A frame keeps the size W×H given to it, and its content area stays (W−2)×(H−2), starting at 1-1.

- **Top border:** row 0, a rule across the full width W. A title, if any, sits in it from column 0, underlined, cut off at the frame's edge.
- **Bottom border:** row H−1, a rule across the full width W.
- **Sides:** no walls. Columns 0 and W−1 of the rows between are blank. This leaves 1 space either side of the content.
- **Scrollbars:** the right column holds a vertical scrollbar. The bottom border holds a horizontal one, whose cells stay underlined (see Scrollbars).
- **Clearing:** the whole frame is cleared, so its blank sides cover what is under them.

```
{u:Title                         }
                              ▐
 content ...                  ▐
 content ...
{u: ▄▄▄▄▄▖                       }
```

### Tabs

To be iterated on. The active tab is bold and underlined, and inactive tabs are plain. Separate tabs with 2 spaces and put a rule on the next row.

```
{b:deploy}   {bu:files}  git  logs
{u:                                  }
```

### List selection

- **Focused pane:** the whole row is negative (focus), with 1 space of padding at each end.
- **Unfocused pane:** the selected row is bold only.

### Tree

**Signs.** `+` marks a collapsed node and `-` an expanded one. Leaves leave the 2-column sign slot blank.

**Indentation.** Names align in a column. Each depth level moves the name 4 columns right, and the sign hangs 2 columns to the left of the name.

**No connector lines.** Indentation alone shows the structure.

**Sticky ancestor path.** When ancestor rows have scrolled off the top of the pane, pin them at the top, one line per ancestor, outermost first, each laid out as its row. The last pinned line is underlined across the pane's width, a rule between the pinned lines and the rows scrolling beneath. For now the pinned lines are drawn only, not interactive. This calls for a header scroll component, a scroll area with pinned header lines (phase 2).

```
- notes/
      abc.txt
      xyz.txt
+ data/
- images/
      123.gif
      456.bmp
    + thumbnails/
```

### Checkboxes

`[ ]` unselected, `[x]` selected, `[-]` partial, all in normal video: no attribute marks the state. A checkbox counts as part of the name column. `check_box(Title, Bool)` gains a third value, `partial`, which toggles to `true`. With focus, `[x] Title` is negative as a whole.

The brackets keep `-` and `x` from being read as a tree sign or a status marker. The state is carried by shape, so it stays readable when the row is negative.

```
- [-] images/
      [x] 123.gif
      [ ] 456.bmp
    + [ ] thumbnails/
```

### Status markers

Right-align status markers in a fixed-width column.

| Marker | Meaning | Attribute |
|---|---|---|
| `ok` | success | bold |
| `x` | failure | bold |
| `!` | warning (optionally with a count: `! 2`) | bold |
| `-` | idle or not applicable | faint |
| `~` | pending | faint |

### Table

- **Header row:** bold and underlined, padded so the underline spans the full table width, including the gaps between columns.
- **Columns:** separated by 2 spaces, with no vertical rules. Numbers are right-aligned.

### Buttons

A button keeps the same width whether or not it is focused. Space, Return and a left click activate it, as now. The default action is whichever button has focus initially. The cursor is hidden (see Focus).

- **Unfocused:** `┃label┃`. The heavy lines match the weight of `[ ] + -`.
- **Focused:** the whole button is negative, and the caps swap to `▌` and `▐` (glyph swap, section 3). In negative, each cap fills its inner half, so the button reads as a pill with half-cell padding.

```prolog
tui:alias_drawable(button(Label), hover([negative], Content, G)) :-
    Content = hover([char('▌')], '┃', G) .> Label .> hover([char('▐')], '┃', G).
```

```
{i:▌Delete▐}  ┃Cancel┃      focus on Delete
```

### Progress bar

A progress bar is not interactive: its fill is negative but never toggled (section 2).

- **Fill:** the filled part is negative.
- **Track:** the rest is a rule (underlined spaces).
- **Label:** the label (for example `62%`) starts 1 cell inside the bar. Label cells over the fill are negative. Label cells over the track are underlined, so the track is unbroken.
- **Resolution:** whole cells only, with no fractional glyphs.

```
build  {i: 62%               }{u:           }
```

### Input field

- **Prompt:** a bold `>`, then a space.
- **Field:** underlined spaces to the field's full width.
- **Text:** typed text is plain and underlined.
- **Placeholder:** while there is no value, the placeholder in angle brackets, italic and underlined: `<file name>`. The brackets carry the state; italic makes it stand out, and where italic is not shown the brackets still do. Under focus, no part of the placeholder is shown.
- **Focus:** the prompt and the field are negative as a whole, and the field drops its underline: negated, an underline shows as a thin slice cut from the bottom of the bar. The underline is applied with `unhovered/3`, the other state of the field's hover. The cursor is shown: highlighting removes `negative` from its cell, and a space left blank is underlined, so the cursor is one normal-video underlined cell.

```
{b:>} {tu:<file name>}{u:                    }      unfocused, no value
{b:>} {u:deploy --env pr                }      unfocused
{bi:>}{i: deploy --env pr}{u: }{i:               }      focused, cursor after the text
{bi:>}{i: }{u: }{i:                              }      focused, no value
```

### Modal

`modal(Dialog, Obstructed)` draws Obstructed dimmed, and Dialog over it in a frame. A modal obstructs only what it is given, so one subview can have a modal while another stays usable.

- **Backdrop:** Obstructed is drawn to raw commands, and `faint` is appended to every command's attributes, bold or not: the one place bold and faint combine (section 2). Cells drawn by `highlight/1` stay highlighted.
- **Inert:** the backdrop's commands lose their alias stacks, so no event reaches the obstructed components. The cursor is not restricted: it may cross the backdrop on its way to a component elsewhere.
- **Dialog:** a frame (see Frame), centred on Obstructed's extent. Its rules are at normal intensity.
- **Padding:** content inside the dialog is padded 2 columns.

```
{d:api/        ok 3    web/      -}
{d:   }{u:                            }
{d:   }  {b:Delete 3 files?}
{d:   }  This can't be undone.
{d:   }
{d:   }  {i:▌Delete▐}  ┃Cancel┃
{d:   }{u:                            }
{d:main.tf     ok      vars.tf  ! 2}
```

### Scrollbars

There is no track; draw only the thumb, in normal video, at half-cell resolution: in each cell, the glyph depends on which halves the thumb covers.

- **Vertical:** in the frame's right column (W−1), beside the content. Its right-half glyphs leave a half-cell gap from the content.
- **Horizontal:** in the frame's bottom border (row H−1). Its cells stay underlined, so the border is unbroken; the thumb's lower-half glyphs sit on the rule.

| Halves covered | Vertical | Horizontal | Vertical, focused | Horizontal, focused |
|---|---|---|---|---|
| both | `▐` | `▄` | `█` | `█` |
| leading only (top or left) | `▝` | `▖` | `▀` | `▌` |
| trailing only (bottom or right) | `▗` | `▗` | `▄` | `▐` |
| none | space | space | space | space |

**Focus.** With the cursor anywhere on a scrollbar, its thumb is solid (Focus, section 5): the half-width glyphs of the vertical thumb fill the column's width, and the half-height glyphs of the horizontal thumb fill the row's height, as in the focused columns above. The thumb's length and position do not change. A scrollbar is a unit (Focus, section 5): the cursor is hidden, and an arrow moves it out in one keypress.

A focused row's negative stays inside the content area, so it never reaches the scrollbar's column.

```
row ...   ▗        horizontal:  ▗▄▄▄▖
row ...   ▐
row ...   ▝
```

### Key hints

- **Style:** the key is bold and the action is faint, as in `{b:↵} {d:open}`.
- **Spacing:** separate pairs with 2 spaces.
- **Key names:** Enter and Tab use the glyphs `↵` and `⇥`. Every other key is a word: `q`, `esc`, `^C`.

### Spinner

- **Glyphs:** a braille dot orbiting through `⠁⠂⠄⡀⢀⠠⠐⠈`, bold, at 80–100 ms per frame. A label beside it may be faint, as in `{b:⠂} {d:syncing}`.
- **Completion:** replace the spinner with the status marker.

### Sparkline

- **Glyphs:** `▁▂▃▄▅▆▇█`, one data point per cell. `▁` is the floor, so the baseline is always visible.
- **Constant series:** if every value is the same, draw all cells as `▄`.
- **Intensity:** faint when it is secondary to non-faint numbers in the same row, normal when it is the primary data.

## 6. Glyphs

Unicode only. An ASCII fallback is listed in `ROADMAP.md`.

| Element | Glyph |
|---|---|
| Enter key | `↵` |
| Tab key | `⇥` |
| Truncation | `…` (only when truncating) |
| Spinner | `⠁⠂⠄⡀⢀⠠⠐⠈` |
| Sparkline | `▁▂▃▄▅▆▇█` |
| Buttons | `┃label┃`, focused `▌label▐` |
| Scrollbar thumb | `▐▝▗` / `▄▖▗`, focused `█▀▄` / `█▌▐` |

**Ambiguous width.** `…`, `↵`, `⇥` and `▄▌▐` have ambiguous East Asian width. A terminal set to draw them double width (common in CJK locales) will misplace what follows them. The framework takes every character to be one cell wide (see `ROADMAP.md`). Braille and the quadrants `▖▗▘▝` are always one column.

**Do not use:**
- Nerd Font or Powerline (Private Use Area) glyphs.
- Characters that can render as emoji (`✔ ✖ ⚠ ☑ ▶`), because their width varies by terminal.
- Double or heavy box borders. `┃` in buttons is the only heavy line.

## 7. Motion

- **Timing:** spinners run at 80–100 ms per frame. No transition is longer than 120 ms.

## 8. Color (optional)

- **Inherit the terminal colors:** use its default foreground and background, and never paint the full background.
- **`NO_COLOR`:** the components honour it: they draw no colour when it is set, and all other attributes still apply. The framework itself does not; an app's own colours are its choice.
- **Role:** color only reinforces an existing encoding, for example tinting a status marker.

## 9. Reference screen

```
{b:deploy}   {bu:files}  git  logs
{u:                                          }
{u: - [-] images/                            }
       [x] 120.gif                     {b:ok}  ▗
       [x] 121.gif                     {b:ok}  ▐
       [ ] 123.gif                      {b:x}  ▝
{i:       [ ] 456.bmp                      ~ }
     + [-] thumbnails/                  {d:-}
 + [ ] logs/                            {d:-}

{bu: name     cpu    mem  trend                }
 api      41%   212M  {d:▁▂▃▅▇▆▄▃▂▁▂▃▅▆▇█▆▄▃}
 web      12%    88M  {d:▂▂▁▁▂▃▂▁▁▁▂▂▃▂▁▁▂▂▁▁}
{u:                                          }
 build  {i: 62%               }{u:           }
 {b:>} {u:deploy --env pr               }

 {b:⠂} {d:syncing}          {b:↵} {d:open}  {b:⇥} {d:next}  {b:q} {d:quit}
```

## 10. Open points

1. **Scope.** Phase 1 restyles what exists (`check_box`, `button`, `input`, `scroll`, `frame`, `titled_frame`, a `rule/1`) and the gallery. Phase 2 adds the new components (tabs, list, tree with a header scroll, table header, status markers, progress bar, modal, key hints, spinner, sparkline).
2. **Tabs.** To be iterated on.
3. **Hiding the cursor.** Done in the library: a special style attribute `cursor_hidden`. Hiding is not the absence of a cursor: the cursor still has its position, it is only not drawn. The cursor is drawn last, and its cell is not highlighted if its attributes include `cursor_hidden`. Leaving in one keypress is `unit/1`, which also hides the cursor: it answers arrows with `cursor_by`.
4. **Nested controls** (a table whose row, column or cell can be the control) are allowed, and need no change: the control knows where the cursor is, and draws the hovers for the level in use.
5. **Highlight.** `highlight/1` is likely useful only for the cursor's cell, or for a selection the cursor is involved in (as in ink).
