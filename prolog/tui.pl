:- module(tui,
          [
            op(601, xfy, '.>'),
            op(601, xfy, '.<'),
            op(601, xfy, '.\\/'),
            op(601, xfy, './\\')
          ]).

/** <module> Text User Interface framework

A TUI framework for SWI-Prolog, inspired by TEA (The Elm Architecture):
app/4 runs an app from its state, a view that draws the state, and an
update that turns events into a new state. Components are defined via
the multifile hooks alias_drawable/2 and at_event_is/3.

This module gives the event loop and the core drawables. Ready-made,
styled components are opt-in: load library(tui/components).

## Drawables

A view is a drawable: a term saying what to draw on the grid of
terminal cells. Positions are X-Y, column and row, from 0-0 at the
top-left of where a drawable is drawn. Drawables are drawn in order,
and where two draw the same cell, the one drawn last wins.

  * Text
    An atom, string or number, drawn as its characters on one row. A
    line break is drawn as a character, not as a new row: use
    `column(Drawables)`.

  * chars(Chars)
    A list of characters, on one row.

  * literal(Term)
    Term as written quoted, as by `format("~q", [Term])`.

  * Drawables
    A list of drawables, all drawn at the same origin, in order: later
    ones in front of earlier ones.

  * translate(Offset, Drawable)
    Drawable moved by Offset, DX-DY.

  * X-Y-Drawable
    Short for `translate(X-Y, Drawable)`.

  * port(Size, Drawable)
    Drawable clipped to W×H cells, Size being W-H.

  * port(Size, Drawable, Extent)
    As `port(Size, Drawable)`, with Extent unified with the furthest
    cell Drawable draws, MaxX-MaxY, clipped or not.

  * zone(Size, Drawable)
    Drawable, taking W×H cells whatever it draws (it is not clipped).
    The view is drawn in a zone the size of the terminal.

  * align(Dir, Drawable)
    Drawable placed against the edges of the zone it is directly in (or
    in that zone's list): Dir is `up_left`, `up`, `up_right`, `left`,
    `center`, `right`, `down_left`, `down` or `down_right`. Elsewhere,
    just Drawable.

  * style(Attributes, Drawable)
    Drawable with Attributes, a list (see below). When styles nest, the
    innermost wins.

  * raw(Commands)
    A drawable already drawn, as given by drawable_raw_extent/3.

Drawables are placed next to each other with four operators, exported
by this module. Each pair has the same layout, and differs only in
which side is drawn last, so is in front where they overlap (when one
is translated, or draws beyond its extent):

  - ``A .> B``: A, then B to its right, B drawn last
  - ``B .< A``: the same layout, A then B to its right, A drawn last
  - ``A .\/ B``: A, then B below it, B drawn last
  - ``B ./\ A``: the same layout, A then B below it, A drawn last

Any other term is an alias, expanded by alias_drawable/2: the core
aliases, such as `row(Drawables)` and `unit(Drawable)`, and those of
opt-in libraries, such as `button(Label)`. They are all documented
there.

## Attributes

  - `bold`, `faint`, `italic`, `underline`, `negative`, `crossed_out`
  - colours `fg(C)` and `bg(C)`, and the bright `hfg(C)` and `hbg(C)`:
    C is `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`,
    `white`, `default`, or an index 0..255; and `fg(R, G, B)`,
    `bg(R, G, B)`
  - `char(C)`: each character drawn shows as C, a character one column
    wide
  - `cursor_hidden`: the cursor is not shown on what is drawn (it keeps
    its position)

@author Mark Bolusmjak
@see app/4
*/

'#imports'.

:- reexport(library(tui/utils), [direction/1, limits_direction_from_to/4]).
:- reexport(library(tui/drawable), [drawable_raw_extent/3]).
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
%    * Key:Drawable
%      Draws Drawable, tagged with Key, so that its events name it: an event
%      Name-Value from the component Drawable, Name being its name, becomes
%      Key-Value. Other events pass unchanged. For example, with
%
%      ```
%      scroll(Id) : scroll(20-15, Offset, Content)
%      ```
%
%      update receives scroll(Id)-(0-5) where the scroll produced scroll-(0-5).
%
%    * box(Size, Chars)
%      The border of a W×H box, Size being W-H; the inside is not drawn.
%      Chars is either `box_chars(Horizontal, Vertical, TopLeft, TopRight,
%      BottomLeft, BottomRight)`, or one of the standard sets `thin`, `thick`,
%      `double`.
%
%    * clear(Size)
%      A W×H rectangle of spaces (Size being W-H) in the enclosing style,
%      covering what is under it.
%
%    * column(Drawables)
%      Drawables stacked top to bottom, using ``.\/``.
%
%    * cursor(Drawable)
%      Drawable, with the cursor on its top-left cell. This overrides any
%      cursor in the state update produced. If several are drawn, the
%      top-left cell of them all wins; if Drawable draws nothing, it places
%      no cursor.
%
%    * highlight(Drawable)
%      Drawable, highlighted as the cursor's cell is, so that it stands out
%      whatever its style. A cell in several highlights is highlighted once.
%
%    * hover(Style, Term)
%      Draws Term, with the attributes Style added while the cursor is on it.
%
%    * hover(Style, Term, Group)
%      As `hover(Style, Term)`, in the hover group Group: an unbound variable
%      that hovers sharing it turn on together, when the cursor is over any of
%      them. For example, a button whose end caps change shape on focus:
%
%      ```
%      tui:alias_drawable(button(Text), hover([negative], Content, G)) :-
%          Content = hover([char('▌')], '┃', G) .> Text
%                 .> hover([char('▐')], '┃', G).
%      ```
%
%    * image(Id, Source, Size)
%      The image Source, under Id, shown in W×H cells, Size being W-H. Id is
%      an integer from 1 to 16777215, unique to the image; W and H are from 1
%      to 297. Source is one of:
%
%        - `png(Bytes)`: a PNG file's contents
%        - `rgba(PW-PH, Bytes)`: PW×PH pixels, 4 bytes each
%        - `rgb(PW-PH, Bytes)`: PW×PH pixels, 3 bytes each
%        - `file(Path)`: a file the terminal reads itself (PNG); only when the
%          terminal runs on the same machine
%
%      Bytes is a string or code list of octets (0..255), as read from a
%      binary stream. Text decoded on reading (e.g. as UTF-8) gives a
%      corrupted image; this cannot be detected.
%
%      Only terminals supporting the Kitty graphics protocol show images; see
%      `graphics(Bool)` in the `terminal_properties(Properties)` event.
%      Elsewhere its cells show as unknown characters.
%
%    * line(Char, From, To)
%      Char repeated from point From to point To, inclusive. The line must
%      be horizontal or vertical.
%
%    * row(Drawables)
%      Drawables side by side, left to right, using ``.>``.
%
%    * table(Style, Rows)
%      Rows, lists of drawables, laid out as a grid: each column as wide as
%      its widest cell, each row as tall as its tallest, shorter rows padded
%      with empty cells. An align in a cell aligns within the cell. Style is
%      `empty` (cells abut), `space` (a blank between cells), or `thin`,
%      `thick` or `double` (a border around and between cells).
%
%    * unhovered(Style, Term, Group)
%      The other state of `hover(Style, Term, Group)`: Style applies while
%      Group is off, and is dropped when the cursor turns it on. For example, a
%      field underlined except when focused, where it is negative:
%
%      ```
%      hover([negative], unhovered([underline], Field, G), G)
%      ```
%
%    * unit(Drawable)
%      Draws Drawable as a single location: the user experiences its cells as
%      one. An arrow key leaves it in one keypress, and the cursor is hidden on
%      it, since a position within it would mean nothing. The cursor keeps its
%      position, so moves through units stay consistent. Buttons, check boxes
%      and scrollbars are units.
%
%    * wrapped(Width, Chars)
%      Chars broken into rows of Width characters, top to bottom. The position
%      just after the last character is always on a row, so the last row may
%      be empty.
%
%  ### library(tui/components)
%
%    * button(Label)
%      A button, shown as ``┃Label┃``, highlighted when focused. A unit (see
%      `unit(Drawable)`).
%
%        - `' '`, `return` or `mouse(press, left)` become `button-pressed`
%
%    * check_box(Title, Bool)
%      A check box, shown as ``[x] Title``, ``[ ] Title`` or ``[-] Title`` for
%      Bool `true`, `false` or `partial`, highlighted when focused. A unit (see
%      `unit(Drawable)`).
%
%        - `' '`, `return` or `mouse(press, left)` become `check_box-NewBool`:
%          `true` becomes `false`, the others `true`
%
%    * frame(Size, Contents)
%      A W×H frame (Size being W-H): rules above and below, no side walls, and
%      Contents clipped to the (W-2)×(H-2) inside, from 1-1. It covers what is
%      under it.
%
%    * frame(Size, Contents, Extent)
%      As `frame(Size, Contents)`, with Extent unified with the furthest cell
%      Contents draws, MaxX-MaxY.
%
%    * hscroll(Drawable, Step)
%      Part of `scroll(Size, Offset, Content)`; not meant to be drawn directly.
%
%    * input(Width, Placeholder, Value)
%      A one-line text field Width wide, shown as ``> `` and an underlined
%      field holding Value, or ``<Placeholder>`` while Value is unbound (nothing
%      if Placeholder is `''`). Highlighted when focused, with the cursor shown
%      in it; the cursor stays within the text.
%
%        - a printable character (a one-character atom) is inserted at the
%          cursor
%        - `backspace` deletes before the cursor, `delete` at it
%        - `paste(Text)` inserts Text, its line breaks as spaces
%
%      Each edit becomes `input-NewValue`, NewValue a string.
%
%    * rule(Width)
%      A horizontal rule Width cells long, a hairline along the baseline.
%
%    * scroll(Size, Offset, Content)
%      Content in a frame (see `frame(Size, Contents)`), scrolled by Offset,
%      X-Y (each 0 or negative), with a scrollbar on each axis where it does
%      not fit. A scrollbar is highlighted when focused, and is a unit (see
%      `unit(Drawable)`).
%
%        - `shift+up`, `shift+down`, `shift+left` and `shift+right` drag what
%          is under the cursor: the content a row or column, or on a scrollbar
%          its thumb
%        - `page_up` and `page_down` scroll a page
%        - `mouse(scroll, Dir)` scrolls a row or column
%
%      Each becomes `scroll-NewOffset`; at the limits, nothing.
%
%    * scroll_view(Offset, Limits, PageHeight, Drawable)
%      Part of `scroll(Size, Offset, Content)`; not meant to be drawn directly.
%
%    * titled_frame(Size, Title, Contents)
%      A frame (see `frame(Size, Contents)`) with Title, any drawable, at the
%      start of its top rule.
%
%    * titled_frame(Size, Title, Contents, Extent)
%      As `titled_frame(Size, Title, Contents)`, with Extent as in
%      `frame(Size, Contents, Extent)`.
%
%    * vscroll(Drawable, Step)
%      Part of `scroll(Size, Offset, Content)`; not meant to be drawn directly.
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
