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
wrapped/2), shapes (clear/1, line/3, box/2), tagging (Key:Drawable) and
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
%    * style(Attrs, D)  — push style attributes for D
%    * A .> B           — horizontal concat (A left, B right)
%    * B .< A           — horizontal concat (A rendered first for width)
%    * A .\/ B          — vertical concat (A top, B bottom)
%    * B ./\ A          — vertical concat (A rendered first for height)
%    * [H|T]            — render all drawables overlaid at same origin
%    * Any term matched by alias_drawable/2

:- discontiguous(drawable//5).
:- det(drawable//5).
drawable(Var, _, _, _, _) -->
    { var(Var), !,
      domain_error(drawable, Var)
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
