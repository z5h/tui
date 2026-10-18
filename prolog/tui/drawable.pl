:- module(tui_drawable,
          [
            op(601, xfy, '.>'),
            op(601, xfy, '.<'),
            op(601, xfy, '.\\/'),
            op(601, xfy, './\\'),
            drawable//5,
            drawable_raw/2,
            drawable__normalized_commands__end/3,
            attributes_char_shown/4
          ]).

/** <module> Drawables

A term language for drawing onto a grid of styled characters. Drawables
expand to commands (X-Y)-(Stack-Attrs-Char), where Stack records which
aliases (see tui:alias_drawable/2) produced the character, innermost
first, each as Origin-Alias: Origin is the X-Y offset the alias was
drawn at.

Besides the primitives in drawable//5, this module defines the core
drawables that make no styling choices: layout (row/1, column/1,
wrapped/2, table/2), shapes (clear/1, line/3, box/2), tagging (Key:Drawable) and
cursor/1. Ready-made, styled components are in library(tui/components).
*/

:- use_module(library(tui/utils)).

:- multifile tui:alias_drawable/2.
:- multifile tui:at_event_is/3.


'#commands'.

%!  drawable_raw(+Drawable, -Raw) is det.
%
%  Render Drawable into raw command list wrapped as raw(Commands).
%  Useful for pre-rendering a component for later embedding.
drawable_raw(Drawable, raw(Raw)) :-
    phrase(drawable(Drawable, [], [], 0-0, _), Raw, []).

drawable__normalized_commands__end(Drawables, Deduped, MXY) :-
    phrase(drawable(Drawables, [], [], 1-1, MXY), Commands, []), !,
    keylist_deduped_prioritize_last(Commands, Deduped).

%!  command(+Command) is semidet.
%
%  True if Command is a valid drawing command.
%  A command is (X-Y)-(Stack-Attrs-Char) where X,Y are integers,
%  Stack is the alias component stack (Origin-Alias entries), Attrs is a list of style
%  attributes, and Char is a single-character atom.
:- public(command/1).
command((X-Y)-(Stack-Attrs-C)) :-
    integer(X),
    integer(Y),
    is_list(Attrs),
    is_list(Stack),
    maplist(is_attribute, Attrs),
    atom(C),
    atom_length(C, 1).


'#cells'.

% The attributes and character a cell shows. A concealed cell shows a
% space in its remaining style.
attributes_char_shown(Attrs0, C, Attrs, Char) :-
    attributes_revealed(Attrs0, Attrs1),
    revealed_char_attributes_shown(Attrs1, C, Attrs, Char).

attributes_revealed(A, R) :-
    exclude('='(conceal), A, A1),
    (   A1 = A
    ->  R  = A
    ;   exclude('='(reveal), A1, A2),
        (   A2 = A1
        ->  R = [conceal | A1]
        ;   R = A2
        )
    ).

revealed_char_attributes_shown([conceal | Attrs], _, Attrs, ' ') :- !.
revealed_char_attributes_shown(Attrs, C, Attrs, C).


'#attributes'.

is_stlye_attribute(A) :-
    member(A, [reset,
               bold,
               italic,
               underline,
               negative,
               faint,
               crossed_out]).

is_color_attribute(fg(R, G, B)) :- !,
    maplist(between(0, 255), [R, G, B]).
is_color_attribute(bg(R, G, B)) :- !,
    maplist(between(0, 255), [R, G, B]).
is_color_attribute(A) :-
    ( A = fg(Color)
    ; A = bg(Color)
    ; A = hbg(Color)
    ; A = hfg(Color)
    ),
    my_color(Color).

ansi_attribute(A) :- is_stlye_attribute(A).
ansi_attribute(A) :- is_color_attribute(A).

is_attribute(hide_cursor).
% NOTE: hover is not a drawable concern; style_hovergroup leaks in from
% tui/hover.pl.
is_attribute(style_hovergroup(Style, _G)) :-
    maplist(ansi_attribute, Style).
is_attribute(A) :-
    ansi_attribute(A).

my_color(_).


'#drawables'.

%!  drawable(+Term, +Stack, +Attrs, +XY, -EndXY)// is det.
%
%  DCG that renders a drawable term into a difference list of commands.
%
%  Term is the drawable to render — an atom, string, number, list, or
%  one of the compound drawable terms (see below). Stack is the current
%  alias component stack (used for event routing). Attrs is the current
%  style attribute list. XY is the origin coordinate as X-Y. EndXY is
%  unified with the maximum X-Y coordinate reached.
%
%  Drawable terms:
%    * Atoms, strings, numbers — rendered as character sequences
%    * literal(T)       — render any term as its printed representation
%    * chars(List)      — render a list of characters
%    * raw(Commands)    — embed pre-rendered commands with offset
%    * translate(DX-DY, D) — offset D by DX-DY
%    * X-Y-D            — shorthand for translate(X-Y, D)
%    * port(W-H, D)     — clip D to a W×H viewport
%    * zone(W-H, D)     — D, with extent W×H whatever D draws; aligns
%                         directly in D (or in its list) align to it
%    * align(Dir, D)    — D, aligned to the enclosing zone's edges
%                         (see zone above); elsewhere just D
%    * style(Attrs, D)  — push style attributes for D
%    * A .> B           — horizontal concat (A left, B right)
%    * B .< A           — horizontal concat (A rendered first for width)
%    * A .\/ B          — vertical concat (A top, B bottom)
%    * B ./\ A          — vertical concat (A rendered first for height)
%    * [H|T]            — render all drawables overlaid at same origin
%    * Any term matched by alias_drawable/2
%
%  @error domain_error(drawable, T) if T, drawn anywhere within Term, is
%         none of these.
%  @error instantiation_error if a drawable within Term is unbound.

:- discontiguous(drawable//5).
:- det(drawable//5).
drawable(Var, _, _, _, _) -->
    { var(Var), !,
      instantiation_error(Var)
    }.

drawable(literal(T), Stack, Attr, X-Y, MX-MY) -->
    { atom(T), atom_chars(T, Chars)
    ; string(T), string_chars(T, Chars)
    ; number(T), number_chars(T, Chars)
    ; term_string(T, S), string_chars(S, Chars)
    }, !,
    drawable(chars(Chars), Stack, Attr, X-Y, MX-MY).

drawable(chars([]), _, _, XY, XY) --> !,
    [].

drawable(chars([C|T]), Stack, Attr, X-Y, MX-MY) --> !,
    [ (X-Y)-(Stack-Attr-C)],
    drawable(chars_tail(T), Stack, Attr, X-Y, MX-MY).

drawable(chars_tail([]), _, _, XY, XY) --> !,
    [].

drawable(chars_tail(T), Stack, Attr, X-Y, MX-MY) --> !,
    { NX is X + 1 },
    drawable(chars(T), Stack, Attr, NX-Y, MX-MY), !.

drawable(raw([]), _, _, XY, XY) --> !,
    [].

drawable(raw([H|T]), Stack, Attr, DX-DY, MX-MY) --> !,
    { H = (X-Y)-(StackH-AttrH-C),
      X1 is X + DX,
      Y1 is Y + DY,
      append(AttrH, Attr, Attr1),
      stack_offset_outer_placed(StackH, DX-DY, Stack, Stack1),
      H1 = (X1-Y1)-(Stack1-Attr1-C)
    }, !,
    [H1],
    drawable(raw(T), Stack, Attr, DX-DY, MTX-MTY),
    { MX is max(X1, MTX),
      MY is max(Y1, MTY)
    }.

drawable(A, Stack, Attr, X-Y, MX-MY) -->
    { atom(A), atom_chars(A, Chars)
    ; string(A), string_chars(A, Chars)
    ; number(A), number_chars(A, Chars)
    }, !,
    drawable(chars(Chars), Stack, Attr, X-Y, MX-MY).

drawable([H|T], Stack, Attr, XY, MX-MY) --> !,
    drawable(H, Stack, Attr, XY, MX1-MY1),
    drawable(T, Stack, Attr, XY, MX2-MY2),
    { MX is max(MX1, MX2), MY is max(MY1, MY2) }, !.

drawable([], _, _, XY, XY) --> !, [].

zone_out(X0-Y0, W-H, X-Y-_) :-
     once(( X < X0
     ; Y < Y0
     ; X >= X0 + W
     ; Y >= Y0 + H
     )).

drawable(translate(TX-TY, Drawables), Stack, Attr, DX-DY, MX-MY) --> !,
    { NDX is DX + TX, NDY is DY + TY },
    drawable(Drawables, Stack, Attr, NDX-NDY, MX-MY).

drawable(TX-TY-Drawable, Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(translate(TX-TY, Drawable), Stack, Attr, DX-DY, MX-MY).

drawable(port(W-H, Drawables), Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(port(W-H, Drawables, _MPX-_MPY), Stack, Attr, DX-DY, MX-MY).

drawable(port(W-H, Drawables, MPX-MPY), Stack, Attr, DX-DY, MX-MY) --> !,
    excluding(zone_out(DX-DY, W-H), drawable(Drawables, Stack, Attr, DX-DY, MPX-MPY)),
    { MX is DX + W - 1, MY is DY + H - 1 }.

drawable(zone(W-H, D), Stack, Attr, DX-DY, MX-MY) --> !,
    zone_drawn(W-H, D, Stack, Attr, DX-DY),
    { MX is DX + W - 1, MY is DY + H - 1 }.

drawable(align(_, D), Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(D, Stack, Attr, DX-DY, MX-MY).

drawable(style(Style, Drawables), Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(Drawables, Stack, [Style | Attr ], DX-DY, MX-MY).

drawable(A .> B, Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(A, Stack, Attr, DX-DY, AMX-AMY),
    { WidthA is AMX - DX + 1 },
    drawable(translate(WidthA-0, B), Stack, Attr, DX-DY, BMX-BMY),
    { MX is max(AMX, BMX), MY is max(AMY, BMY) }.

drawable(B .< A, Stack, Attr, DX-DY, MX-MY) --> !,
    { phrase(drawable(A, Stack, Attr, DX-DY, AMX-AMY), Raw, []),
      WidthA is AMX - DX + 1
    },
    drawable(translate(WidthA-0, B), Stack, Attr, DX-DY, BMX-BMY),
    drawable(raw(Raw), [], [], 0-0, _-_),
    { MX is max(AMX, BMX), MY is max(AMY, BMY) }.

drawable(A .\/ B, Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(A, Stack, Attr, DX-DY, AMX-AMY),
    { HeightA is AMY - DY + 1 },
    drawable(translate(0-HeightA, B), Stack, Attr, DX-DY, BMX-BMY),
    { MX is max(AMX, BMX), MY is max(AMY, BMY) }.

drawable(B ./\ A, Stack, Attr, DX-DY, MX-MY) --> !,
    { phrase(drawable(A, Stack, Attr, DX-DY, AMX-AMY), Raw, []),
      HeightA is AMY - DY + 1
    },
    drawable(translate(0-HeightA, B), Stack, Attr, DX-DY, BMX-BMY),
    drawable(raw(Raw), [], [], 0-0, _-_),
    { MX is max(AMX, BMX), MY is max(AMY, BMY) }.

drawable(A, Stack, Attr, DX-DY, MX-MY) -->
    { tui:alias_drawable(A, D) }, !,
    drawable(D, [(DX-DY)-A | Stack], Attr, DX-DY, MX-MY).

drawable(D, _, _, _, _) -->
    { domain_error(drawable, D) }.

% The stack of a raw command placed at offset DX-DY inside Outer: its
% origins move with it, then Outer follows.
stack_offset_outer_placed(Stack, 0-0, Outer, Placed) :- !,
    append(Stack, Outer, Placed).
stack_offset_outer_placed([], _, Outer, Outer).
stack_offset_outer_placed([(OX-OY)-A | T], DX-DY, Outer, [(OX1-OY1)-A | T1]) :-
    OX1 is OX + DX,
    OY1 is OY + DY,
    stack_offset_outer_placed(T, DX-DY, Outer, T1).


'#zones'.

% The items of a drawable: its elements if it is a list (nested lists
% flattened), otherwise itself.
drawable_items(D, Items) :-
    phrase(items(D), Items).

items([]) --> !, [].
items([H | T]) --> !, items(H), items(T).
items(D) --> [D].

% The items of a W×H zone, drawn: an align is measured and moved to the
% zone's edges, anything else is drawn as it is. Walks lists in place,
% since a view may be a long one.
zone_drawn(_, [], _, _, _) --> !, [].
zone_drawn(WH, [H | T], Stack, Attr, XY) --> !,
    zone_drawn(WH, H, Stack, Attr, XY),
    zone_drawn(WH, T, Stack, Attr, XY).
zone_drawn(WH, align(Dir, D), Stack, Attr, XY) --> !,
    { drawable_raw_extent(D, Raw, E),
      zone_direction_extent_placed(WH, Dir, E, Raw, Placed)
    },
    drawable(Placed, Stack, Attr, XY, _).
zone_drawn(_, D, Stack, Attr, XY) -->
    drawable(D, Stack, Attr, XY, _).

% Raw drawn at an offset from a W×H zone's top-left, so that its extent
% E lies against the zone's edges in direction Dir.
zone_direction_extent_placed(W-H, Dir, EW-EH, Raw, OX-OY-Raw) :-
    (   direction_horizontal_vertical(Dir, HA, VA)
    ->  true
    ;   domain_error(align_direction, Dir)
    ),
    size_alignment_extent_offset(W, HA, EW, OX),
    size_alignment_extent_offset(H, VA, EH, OY).

direction_horizontal_vertical(up_left,    start,  start).
direction_horizontal_vertical(up,         middle, start).
direction_horizontal_vertical(up_right,   end,    start).
direction_horizontal_vertical(left,       start,  middle).
direction_horizontal_vertical(center,     middle, middle).
direction_horizontal_vertical(right,      end,    middle).
direction_horizontal_vertical(down_left,  start,  end).
direction_horizontal_vertical(down,       middle, end).
direction_horizontal_vertical(down_right, end,    end).

% Uneven centring leans up and left.
size_alignment_extent_offset(_, start, _, 0).
size_alignment_extent_offset(S, middle, E, O) :- O is (S - E) div 2.
size_alignment_extent_offset(S, end, E, O) :- O is S - E.

% D rendered at 0-0, and its extent: from 0-0 to the furthest cell drawn.
% A drawable that draws nothing measures 1×1.
drawable_raw_extent(D, raw(Raw), W-H) :-
    phrase(drawable(D, [], [], 0-0, MX-MY), Raw),
    W is MX + 1,
    H is MY + 1.


'#layout'.

%!  column(+Drawables)
%
%  Drawables stacked top to bottom, using .\/.
tui:alias_drawable(column([H]), H) :- !.
tui:alias_drawable(column([]), []) :- !.
tui:alias_drawable(column([H|T]), (H .\/ column(T))) :- !.

%!  row(+Drawables)
%
%  Drawables side by side, left to right, using .>.
tui:alias_drawable(row([H]), H) :- !.
tui:alias_drawable(row([]), []) :- !.
tui:alias_drawable(row([H|T]), (H .> row(T))) :- !.

%!  wrapped(+Width, +Chars)
%
%  Chars broken into rows of Width characters, top to bottom. N chars
%  take N // Width + 1 rows, so the position just after the last char
%  always lies on a row (the last row may be empty).
tui:alias_drawable(wrapped(W, Chars), column(Rows)) :-
    width_chars_rows(W, Chars, Rows).

width_chars_rows(W, Chars, [chars(Row) | Rows]) :-
    (   length(Row, W),
        append(Row, Rest, Chars)
    ->  width_chars_rows(W, Rest, Rows)
    ;   Row = Chars,
        Rows = []
    ).

%!  table(+Style, +Rows)
%
%  Rows, lists of drawables, laid out as a grid: each column as wide as
%  its widest cell, each row as tall as its tallest. Shorter rows have
%  trailing empty cells. Each cell is drawn as a zone of its column's
%  width and its row's height, so an align in a cell aligns within it.
%  Style is empty (cells abut), space (a blank between cells), or a box
%  style, thin, thick or double (a border around and between cells).
tui:alias_drawable(table(Style, Rows0), Table) :-
    style_border_gap(Style, B, G),
    rows_padded(Rows0, Rows),
    (   Rows = [[_ | _] | _]
    ->  maplist(maplist(cell_measured), Rows, Measured),
        rows_widths(Measured, Ws),
        maplist(row_height, Measured, Hs),
        sizes_start_gap_positions(Ws, B, G, Xs),
        sizes_start_gap_positions(Hs, B, G, Ys),
        maplist(row_cells(Xs, Ws), Measured, Ys, Hs, Cells),
        style_table_border(Style, Xs, Ws, Ys, Hs, Border),
        Table = [Border | Cells]
    ;   Table = []
    ).

style_border_gap(empty, 0, 0) :- !.
style_border_gap(space, 0, 1) :- !.
style_border_gap(Style, 1, 1) :-
    (   style_box_chars(Style, _)
    ->  true
    ;   domain_error(table_style, Style)
    ).

rows_padded(Rows0, Rows) :-
    foldl(row_length_max, Rows0, 0, N),
    maplist(length_row_padded(N), Rows0, Rows).

row_length_max(Row, N0, N) :-
    length(Row, L),
    N is max(N0, L).

length_row_padded(N, Row0, Row) :-
    length(Row, N),
    append(Row0, Pad, Row),
    maplist(=([]), Pad).

% A cell rendered once: its items, each with its raw commands and extent,
% and the cell's extent.
cell_measured(Cell, cell(Items, E)) :-
    drawable_items(Cell, Items0),
    maplist(item_measured, Items0, Items),
    foldl(item_extent_max, Items, 1-1, E).

item_measured(align(Dir, D), aligned(Dir, Raw, E)) :- !,
    drawable_raw_extent(D, Raw, E).
item_measured(D, plain(Raw, E)) :-
    drawable_raw_extent(D, Raw, E).

item_extent_max(Item, W0-H0, W-H) :-
    (   Item = aligned(_, _, IW-IH)
    ;   Item = plain(_, IW-IH)
    ), !,
    W is max(W0, IW),
    H is max(H0, IH).

rows_widths([Row | Rows], Ws) :-
    maplist(cell_width, Row, Ws0),
    foldl(row_widths_max, Rows, Ws0, Ws).

row_widths_max(Row, Ws0, Ws) :-
    maplist(cell_width, Row, RWs),
    maplist(max_of, RWs, Ws0, Ws).

cell_width(cell(_, W-_), W).

row_height(Row, H) :-
    foldl(cell_height_max, Row, 0, H).

cell_height_max(cell(_, _-CH), H0, H) :-
    H is max(H0, CH).

max_of(A, B, M) :-
    M is max(A, B).

% Where each of a sequence of sizes starts, from Start, Gap apart.
sizes_start_gap_positions([], _, _, []).
sizes_start_gap_positions([S | Ss], P, G, [P | Ps]) :-
    P1 is P + S + G,
    sizes_start_gap_positions(Ss, P1, G, Ps).

row_cells(Xs, Ws, Row, Y, H, Cells) :-
    maplist(cell_x_width_placed(Y, H), Row, Xs, Ws, Cells).

% A measured cell as a zone, its items already placed.
cell_x_width_placed(Y, H, cell(Items, _), X, W, X-Y-zone(W-H, Placed)) :-
    maplist(measured_placed(W-H), Items, Placed).

measured_placed(WH, aligned(Dir, Raw, E), Placed) :-
    zone_direction_extent_placed(WH, Dir, E, Raw, Placed).
measured_placed(_, plain(Raw, _), Raw).

% A box around each cell, adjacent boxes sharing edges, drawn row by row
% and merged where they meet.
style_table_border(Style, Xs, Ws, Ys, Hs, raw(Merged)) :-
    (   style_box_chars(Style, _)
    ->  findall(BX-BY-box(BW-BH, Style),
                ( nth0(I, Ys, Y), nth0(I, Hs, H),
                  nth0(J, Xs, X), nth0(J, Ws, W),
                  BX is X - 1, BY is Y - 1,
                  BW is W + 2, BH is H + 2 ),
                Boxes),
        drawable_raw(Boxes, raw(Commands)),
        commands_merged(Commands, Merged)
    ;   Merged = []
    ).


'#shapes'.

%!  clear(+W-+H)
%
%  A W×H rectangle of spaces with reset styling. Used to erase a region
%  before drawing over it.
tui:alias_drawable(clear(W-H), style([reset, bg(default)], Spaces)) :-
    W1 is W - 1,
    H1 is H - 1,
    findall((X-Y)-' ',
            ( between(0, W1, X),
              between(0, H1, Y) ),
            Spaces).

%!  line(+Char, +From, +To)
%
%  Char repeated from point From to point To, inclusive. The line must
%  be horizontal or vertical.
tui:alias_drawable(line(Char, From, To), Line) :-
    char_from_to_line(Char, From, To, Line).

char_from_to_line(C, X-Y, X-Y, [X-Y-C]) :- !.
char_from_to_line(C, X1-Y, X2-Y, [X1-Y-C | Tail]) :- !,
    at_towards_next(X1, X2, Next),
    char_from_to_line(C, Next-Y, X2-Y, Tail).
char_from_to_line(C, X-Y1, X-Y2, [X-Y1-C | Tail]) :- !,
    at_towards_next(Y1, Y2, Next),
    char_from_to_line(C, X-Next, X-Y2, Tail).

% Next is one step from At towards Towards; fails if they are equal.
at_towards_next(At, Towards, Next) :-
    (   At < Towards
    ->  Next is At + 1
    ;   At > Towards
    ->  Next is At - 1
    ;   fail
    ).

%!  box(+W-+H, +Chars)
%
%  The border of a W×H box; the inside is not drawn. Chars is either
%  box_chars(Horizontal, Vertical, TopLeft, TopRight, BottomLeft,
%  BottomRight), or one of the standard sets thin, thick, double.
tui:alias_drawable(box(W-H, Style), box(W-H, Chars)) :-
    atom(Style), !,
    style_box_chars(Style, Chars).
tui:alias_drawable(box(W0-H0, box_chars(Hz, Vt, TL, TR, BL, BR)),
                   [Top, Bottom, Left, Right, Corners]) :-
    W is W0 - 1,
    H is H0 - 1,
    Corners = [(0-0)-TL, (W-0)-TR, (0-H)-BL, (W-H)-BR],
    WM is W - 1,
    HM is H - 1,
    Top    = line(Hz, 1-0, WM-0),
    Bottom = line(Hz, 1-H, WM-H),
    Left   = line(Vt, 0-1, 0-HM),
    Right  = line(Vt, W-1, W-HM).

style_box_chars(thin,   box_chars('─', '│', '┌', '┐', '└', '┘')).
style_box_chars(thick,  box_chars('━', '┃', '┏', '┓', '┗', '┛')).
style_box_chars(double, box_chars('═', '║', '╔', '╗', '╚', '╝')).

corners_unified(['╝', '╚', '╗', '╔'], '╬').
corners_unified(['╗', '╔'], '╦').
corners_unified(['╝', '╚'], '╩').
corners_unified(['╚', '╔'], '╠').
corners_unified(['╝', '╗'], '╣').

corners_unified(['┛', '┗', '┓', '┏'], '╋').
corners_unified(['┓', '┏'], '┳').
corners_unified(['┛', '┗'], '┻').
corners_unified(['┗', '┏'], '┣').
corners_unified(['┛', '┓'], '┫').

corners_unified(['┘', '└', '┐', '┌'], '┼').
corners_unified(['┐', '┌'], '┬').
corners_unified(['┘', '└'], '┴').
corners_unified(['└', '┌'], '├').
corners_unified(['┘', '┐'], '┤').

% Commands drawn at the same cell, merged into one: identical characters
% into that character, corners that meet into their junction. Otherwise
% the last drawn wins. keysort is stable, so each cell's characters stay
% in the order drawn.
commands_merged(Commands, Merged) :-
    keysort(Commands, Sorted),
    group_pairs_by_key(Sorted, Groups),
    maplist(group_merged, Groups, Merged).

group_merged(XY-Drawn, XY-(Stack-Attrs-C)) :-
    Drawn = [Stack-Attrs-_ | _],
    findall(C0, member(_-_-C0, Drawn), Cs0),
    list_to_set(Cs0, Cs),
    (   Cs = [C]
    ->  true
    ;   corners_unified(Cs, C)
    ->  true
    ;   last(Cs, C)
    ).


'#tagging'.

%!  Key:Drawable
%
%  Drawable, tagged with Key for event routing; Key does not affect
%  drawing.
%
%  When a component event Name-Value bubbles through Key:Component, and
%  Name is the functor of Component, the event becomes Key-Value: the
%  component's own name is replaced by the tag. Events from components
%  nested deeper (other names) and raw events (up, ' ', ...) pass
%  through unchanged.
%
%  Example:
%
%      scroll(Id) : scroll(20-15, Offset, Content)
%
%  turns scroll-(0-5) from the scroll into scroll(Id)-(0-5).
tui:alias_drawable(_:D, D).

tui:at_event_is(Key:Inner, _-(Name-Value), Key-Value) :-
    functor(Inner, Name, _).


'#cursor'.

%!  cursor(+Drawable)
%
%  Drawable, with the cursor on its top-left cell. This overrides any
%  cursor in the state update produced. If several are drawn, the
%  top-left cell of them all wins; if Drawable draws nothing, it places
%  no cursor.
tui:alias_drawable(cursor(D), D).
