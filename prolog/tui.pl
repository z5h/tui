:- module(tui,
          [
            op(601, xfy, '.>'),
            op(601, xfy, '.<'),
            op(601, xfy, '.\\/'),
            op(601, xfy, './\\')
          ]).

/** <module> Text User Interface framework

A TUI framework for SWI-Prolog, inspired by TEA (The Elm Architecture).
Components are defined via the multifile hooks alias_drawable/2 and
at_event_is/3.

This module gives the event loop and the core drawables. Ready-made,
styled components are opt-in: load library(tui/components).

@author Mark Bolusmjak
@see app/4
*/

'#imports'.

:- reexport(library(tui/utils), [direction/1, limits_direction_from_to/4]).
:- reexport(library(tui/drawable), [drawable//5, drawable_raw/2]).
:- reexport(library(tui/events), [stack_event_is/3]).
:- reexport(library(tui/loop), [app/4, app/5]).
:- reexport(library(tui/subscriptions), [port_send/2]).


'#hooks'.

%!  alias_drawable(+DrawableTerm, -ExpandedDrawable) is semidet.
%
%  Multifile hook. Define custom drawable components by mapping a term
%  to its drawable expansion. During rendering the alias is pushed onto
%  the component stack so that at_event_is/3 can intercept events.
%
%  DrawableTerm must be compound: atoms, strings and numbers always draw
%  as text, so a clause for one is never used. Write a component without
%  arguments with empty parentheses, e.g. logo().
%
%  ## Aliases
%
%  ### Core
%
%  #### `Key:Drawable`
%
%  Draws Drawable, tagged with Key for event routing; Key does not affect
%  drawing. When a component event Name-Value bubbles through
%  Key:Component, and Name is the functor of Component, the event becomes
%  Key-Value: the component's own name is replaced by the tag. Events from
%  components nested deeper (other names) and raw events (up, ' ', ...)
%  pass through unchanged. For example,
%
%  ```
%  scroll(Id) : scroll(20-15, Offset, Content)
%  ```
%
%  turns scroll-(0-5) from the scroll into scroll(Id)-(0-5).
%
%  #### `box(Size, Chars)`
%
%  The border of a W×H box, Size being W-H; the inside is not drawn.
%  Chars is either `box_chars(Horizontal, Vertical, TopLeft, TopRight,
%  BottomLeft, BottomRight)`, or one of the standard sets `thin`, `thick`,
%  `double`.
%
%  #### `clear(Size)`
%
%  A W×H rectangle of spaces, Size being W-H, in the enclosing style: it
%  covers what is under it with the surrounding background, before
%  drawing over it.
%
%  #### `column(Drawables)`
%
%  Drawables stacked top to bottom, using ``.\/``.
%
%  #### `cursor(Drawable)`
%
%  Drawable, with the cursor on its top-left cell. This overrides any
%  cursor in the state update produced. If several are drawn, the
%  top-left cell of them all wins; if Drawable draws nothing, it places
%  no cursor.
%
%  #### `highlight(Drawable)`
%
%  Drawable, each cell inverted so that it stands out whatever its style:
%  negative is added, or removed if the cell is negative. A negative
%  space without underline on the default background would then be
%  blank, so it loses negative and is underlined instead (in its
%  foreground colour). Highlighting is idempotent: a cell inside several
%  highlights is highlighted once. The cursor's cell is highlighted the
%  same way. Like `cursor(Drawable)`, it changes no style here: the cells
%  it draws carry it in their alias stack, and rendering highlights them.
%
%  #### `hover(Style, Term)`
%
%  Wrap Term with a hover highlight. When the cursor is over this
%  component, Style attributes are applied.
%
%  #### `hover(Style, Term, Group)`
%
%  As `hover(Style, Term)`, in the hover group Group: an unbound variable
%  that hovers sharing it turn on together, when the cursor is over any of
%  them. For example, a button whose end caps change shape on focus:
%
%  ```
%  tui:alias_drawable(button(Text), hover([negative], Content, G)) :-
%      Content = hover([char('▌')], '┃', G) .> Text
%             .> hover([char('▐')], '┃', G).
%  ```
%
%  #### `image(Id, Source, Size)`
%
%  The image Source, under Id, shown in W×H cells, Size being W-H. Id is
%  an integer from 1 to 16777215, unique to the image; W and H are from 1
%  to 297. Source is one of:
%
%    - `png(Bytes)`: a PNG file's contents
%    - `rgba(PW-PH, Bytes)`: PW×PH pixels, 4 bytes each
%    - `rgb(PW-PH, Bytes)`: PW×PH pixels, 3 bytes each
%    - `file(Path)`: a file the terminal reads itself (PNG); only when the
%      terminal runs on the same machine
%
%  Bytes is a string or code list of octets (0..255), as read from a
%  binary stream. Text decoded on reading (e.g. as UTF-8) gives a
%  corrupted image; this cannot be detected.
%
%  Only terminals supporting the Kitty graphics protocol show images; see
%  `graphics(Bool)` in the `terminal_properties(Properties)` event.
%  Elsewhere the placeholders show as unknown characters.
%
%  #### `line(Char, From, To)`
%
%  Char repeated from point From to point To, inclusive. The line must
%  be horizontal or vertical.
%
%  #### `row(Drawables)`
%
%  Drawables side by side, left to right, using ``.>``.
%
%  #### `table(Style, Rows)`
%
%  Rows, lists of drawables, laid out as a grid: each column as wide as
%  its widest cell, each row as tall as its tallest. Shorter rows have
%  trailing empty cells. Each cell is drawn as a zone of its column's
%  width and its row's height, so an align in a cell aligns within it.
%  Style is empty (cells abut), space (a blank between cells), or a box
%  style, thin, thick or double (a border around and between cells).
%
%  #### `unhovered(Style, Term, Group)`
%
%  The other state of `hover(Style, Term, Group)`: Style applies while
%  Group is off, and is dropped when the cursor turns it on. For example, a
%  field underlined except when focused, where it is negative:
%
%  ```
%  hover([negative], unhovered([underline], Field, G), G)
%  ```
%
%  #### `unit(Drawable)`
%
%  Draws Drawable as a unit: though it covers many cells of the grid, the
%  user experiences them as a single location. An arrow key moves the
%  cursor out of it in one keypress, through the side in the arrow's
%  direction, as it would leave a single cell. For the same reason the
%  cursor is hidden on it (`cursor_hidden`): showing a position within a
%  unit would contradict that experience. The cursor still keeps its
%  position, so that its moves through units are consistent: leaving a
%  unit by `up`, it arrives above where it was placed in it.
%
%  The sides are those of the extent Drawable draws, from the origin it is
%  drawn at to its furthest cell. Buttons, check boxes and scrollbars are
%  units.
%
%  Events produced:
%
%    - `cursor_by(DX-DY)` on `up`, `down`, `left` or `right`, to the cell
%      just past the side in that direction. On a side's own cells the
%      arrow is not taken: the cursor's usual one-cell move leaves the
%      unit, and bubbles `arrived(Dir)` where it lands.
%
%  #### `wrapped(Width, Chars)`
%
%  Chars broken into rows of Width characters, top to bottom. N chars
%  take N // Width + 1 rows, so the position just after the last char
%  always lies on a row (the last row may be empty).
%
%  ### library(tui/components)
%
%  #### `button(Label)`
%
%  A button, shown as ``┃Label┃``. With the cursor on it, it is negative
%  and its caps become ``▌`` and ``▐``, a pill with half-cell padding. It
%  is a unit (`unit(Drawable)`): the cursor is hidden on it, and an arrow
%  moves it out in one keypress.
%
%  Events produced:
%
%    - `button-pressed` on `' '` (space), `return` or `mouse(press, left)`
%
%  #### `check_box(Title, Bool)`
%
%  A toggleable checkbox: ``[x]``, ``[ ]`` or ``[-]`` (Bool true, false or
%  partial), then Title. With the cursor on it, box and title are
%  negative together. It is a unit (`unit(Drawable)`): the cursor is
%  hidden on it, and an arrow moves it out in one keypress.
%
%  Events produced:
%
%    - `check_box-NewBool` on `' '` (space), `return` or
%      `mouse(press, left)`: true becomes false, false and partial become
%      true
%
%  #### `frame(Size, Contents)`
%
%  A frame W×H, Size being W-H, containing Contents in a viewport. Its
%  top and bottom rows are rules across the full width; it has no side
%  walls. The viewport is (W-2)×(H-2), from 1-1, leaving a blank column
%  either side (the right one takes a vertical scrollbar, see
%  `scroll(Size, Offset, Content)`). The whole frame is cleared before
%  rendering.
%
%  #### `frame(Size, Contents, Extent)`
%
%  As `frame(Size, Contents)`; Extent is unified with the MaxX-MaxY of the
%  content (useful for scrolling).
%
%  #### `hscroll(Drawable, Step)`
%
%  Draws Drawable, a horizontal scrollbar. Meant for
%  `scroll(Size, Offset, Content)`: on it, `shift+left` and `shift+right`
%  become `thumb_dragged(Dir, Step)`, which the enclosing
%  `scroll_view(Offset, Limits, PageHeight, Drawable)` turns into
%  scrolling the content Step columns the other way. It is a unit
%  (`unit(Drawable)`): the cursor is hidden on it, and an arrow moves it
%  out in one keypress.
%
%  #### `input(Width, Placeholder, Value)`
%
%  A one-line text field Width wide, underlined, after a bold ``> ``.
%  Shows Value, or while Value is unbound, the Placeholder in angle
%  brackets, italic (none if Placeholder is empty). Text beyond Width is
%  not shown. With the cursor on it, prompt and field are negative and the
%  field loses its underline (a negative underline would show as a slice
%  cut from the bar); the cursor is shown in it, and the placeholder is
%  not.
%
%  The cursor stays where text can be edited: on `arrived(Dir)` or
%  `mouse(press, left)` past the end of the text (trailing spaces are
%  text; the padding to Width is not), or on the ``> ``, it moves to the
%  nearest such cell.
%
%  With the cursor in the field:
%
%    - a one-character atom (code 32 or above, but not 127) is inserted
%      at the cursor (at the end of the text, if the cursor is past it),
%      and the cursor advances
%    - `backspace` deletes before the cursor, `delete` at it
%    - `paste(Text)` inserts Text, its line breaks as spaces
%
%  Events produced:
%
%    - `input-NewValue`, NewValue a string, followed by `cursor_by(DX-0)`
%      if the cursor must move to stay after the edit
%    - `cursor_by(DX-0)` alone, moving an arriving cursor to where text can
%      be edited
%    - `noop` for an edit that changes nothing (`backspace` at the start,
%      `delete` at the end), so that it does not bubble on
%
%  #### `rule(Width)`
%
%  A horizontal rule Width cells long: spaces drawn underlined, a
%  hairline along the baseline.
%
%  #### `scroll(Size, Offset, Content)`
%
%  A scrollable frame (see `frame(Size, Contents)`). Content is rendered
%  in a W×H frame's viewport (Size being W-H), offset by Offset,
%  ScrollX-ScrollY (each 0 or negative). On each axis where the content
%  does not fit, a scrollbar shows its thumb, with half-cell resolution
%  and no track: vertical in the frame's right column, horizontal in its
%  bottom rule. With the cursor on a scrollbar, its thumb is solid: the
%  half blocks fill the whole width of the column, or the whole height of
%  the row. A scrollbar is a unit (`unit(Drawable)`): the cursor is hidden
%  on it, and an arrow moves it out in one keypress.
%
%  `shift+up`, `shift+down`, `shift+left` and `shift+right` drag what is
%  under the cursor, as with a mouse:
%
%    - anywhere in the frame, the content, one row or column per press
%    - on a scrollbar, along its axis, the thumb, one half-cell per press
%
%  `page_up` and `page_down` move by a page (the viewport's height less
%  one row, at least one), anywhere in the frame. With the mouse (see
%  app/5), `mouse(scroll, Dir)` scrolls the content a row or column at a
%  time.
%
%  Events produced:
%
%    - `scroll-(NewX-NewY)`, the new offset
%    - `noop` for an event that would move past the limits, so that it
%      does not bubble on
%
%  #### `scroll_view(Offset, Limits, PageHeight, Drawable)`
%
%  Draws Drawable. Meant for `scroll(Size, Offset, Content)`, which draws
%  its frame and scrollbars with it, so that its events find, on the alias
%  stack, what they need: Offset, the content's offset; Limits, MaxH-MaxV,
%  how far the content can scroll on each axis (0 or positive); and
%  PageHeight, the viewport's height. The events it takes are those of
%  `scroll(Size, Offset, Content)`.
%
%  #### `titled_frame(Size, Title, Contents)`
%
%  A frame (see `frame(Size, Contents)`) with Title in its top rule, from
%  its first column, underlined and cut off at the frame's edge. Title is
%  any drawable.
%
%  #### `titled_frame(Size, Title, Contents, Extent)`
%
%  As `titled_frame(Size, Title, Contents)`, with Extent as in
%  `frame(Size, Contents, Extent)`.
%
%  #### `vscroll(Drawable, Step)`
%
%  Draws Drawable, a vertical scrollbar. Meant for
%  `scroll(Size, Offset, Content)`: on it, `shift+up` and `shift+down`
%  become `thumb_dragged(Dir, Step)`, which the enclosing
%  `scroll_view(Offset, Limits, PageHeight, Drawable)` turns into
%  scrolling the content Step rows the other way. It is a unit
%  (`unit(Drawable)`): the cursor is hidden on it, and an arrow moves it
%  out in one keypress.
%
%  @see at_event_is/3
:- multifile alias_drawable/2.

%!  at_event_is(+AliasOrStack, +PositionedEvent, -RewrittenEvent) is nondet.
%
%  Multifile hook. Rewrite an event as seen by a component on the alias
%  stack. PositionedEvent is X-Y-RawEvent, X-Y being where the event
%  happened, relative to the component's
%  origin (absolute for [], the bottom of the stack; with no cursor, []
%  sees RawEvent alone). Called during event bubbling: each solution
%  replaces the event, and bubbles on from the same component; with
%  none, bubbling continues to the next stack entry. Every event the
%  raw event becomes reaches update, in order.
%
%  A cursor movement bubbles as moved(Direction) from where the cursor
%  was, and, for an arrow key no component claimed, as arrived(Direction)
%  where it lands. The cursor moves regardless; what they are rewritten
%  to is handled with the cursor moved. A mouse event bubbles where it
%  happened (see app/5).
%
%  Besides events for update, a component may produce a direction, which
%  moves the cursor one cell, or cursor_by(DX-DY), which moves it by an
%  offset; e.g. to keep the cursor after an edit, or, answering
%  arrived(Direction), on a cell where it belongs. noop takes the event
%  to do nothing: it bubbles no further, and update never sees it.
%
%  @see stack_event_is/3
:- multifile at_event_is/3.
