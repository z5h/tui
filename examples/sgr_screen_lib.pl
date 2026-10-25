:- module(sgr_screen_lib,
          [
            screen_width/1,
            empty_cell/1,
            string_rows/2,
            rows_string/2,
            attributes_with/3,
            attributes_without/3
          ]).

/** <module> sgr_screen_lib — styled text, replayed onto a screen and written back

A screen is a list of rows, each a list of screen_width/1 (80) cells
Attrs-Char, Attrs being an ordered set of the attributes
attributes_sgr/2 (library(tui/terminal)) takes. An empty cell is an
unstyled space, []-' '. Pure, except that it reads no files: text in,
rows out, and back.

Reading replays the text as a terminal would, onto a screen 80 columns
wide and as tall as it needs to be:

  * printable characters are written at the cursor in the current
    style. Writing in the last column leaves the cursor there, and the
    next character goes to the start of the next row (the deferred wrap
    of xterm).
  * CR; LF, VT and FF (which also return, as through a tty); BS; TAB
    (stops every 8 columns).
  * CSI cursor movement: CUU A, CUD B, CUF C, CUB D, CNL E, CPL F,
    CHA G, HPA `, HPR a, VPA d, VPR e, CUP H, HVP f. Save and restore:
    CSI s and CSI u (the position), ESC 7 and ESC 8 (the position and
    the style). IND ESC D, NEL ESC E, RI ESC M.
  * SGR: 0, 1 bold, 2 faint, 3 italic, 4 underline, 7 negative, 9
    crossed_out, and 22, 23, 24, 27, 29 to undo them; colours 30-37,
    39, 40-47, 49, 90-97, 100-107, and 38/48 with 5;N or 2;R;G;B (also
    in the colon form). Other SGR parameters are ignored.

Everything else (other CSI sequences, OSC and other strings, other
escapes and controls) is parsed and ignored. The cursor never leaves the
screen: its column stays within 0..79, its row at 0 or below. The screen
has as many rows as reach the last row a character was written on or an
LF was received on, so text ending in a newline has no empty row after
it.

Writing gives each row, from the top, on a line of its own: its cells up
to the last that is not empty, styled with SGR (a reset and the cell's
attributes, whenever they change), a reset if any style is on, and LF.
In a terminal at least 80 columns wide `cat` shows the screen, and read
back it gives the same rows.
*/

:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(lists)).
:- use_module(library(ordsets)).
:- use_module(library(tui/terminal), [attributes_sgr/2]).


'#screen'.

%!  screen_width(-Width) is det.
%
%  Every row has Width cells.
screen_width(80).

%!  empty_cell(-Cell) is det.
%
%  Cell is the empty cell, an unstyled space.
empty_cell([]-' ').

%!  attributes_with(+Attrs0, +Attr, -Attrs) is det.
%
%  Attrs is the ordered set Attrs0 with Attr. A colour replaces any
%  colour of its kind (fg, hfg and fg/3 are one kind, bg, hbg and bg/3
%  the other); fg(default) and bg(default) just remove it.
attributes_with(A0, Attr, A) :-
    (   attribute_kind(Attr, Kind)
    ->  exclude(attribute_kind_is(Kind), A0, A1)
    ;   A1 = A0
    ),
    (   memberchk(Attr, [fg(default), bg(default)])
    ->  A = A1
    ;   ord_add_element(A1, Attr, A)
    ).

%!  attributes_without(+Attrs0, +Attr, -Attrs) is det.
%
%  Attrs is the ordered set Attrs0 without Attr.
attributes_without(A0, Attr, A) :-
    ord_del_element(A0, Attr, A).

attribute_kind(fg(_), fg).
attribute_kind(hfg(_), fg).
attribute_kind(fg(_, _, _), fg).
attribute_kind(bg(_), bg).
attribute_kind(hbg(_), bg).
attribute_kind(bg(_, _, _), bg).

attribute_kind_is(Kind, Attr) :-
    attribute_kind(Attr, Kind).


'#reading'.

%!  string_rows(+Text, -Rows) is det.
%
%  Rows is the screen Text draws, replayed as described above.
string_rows(S, Rows) :-
    string_chars(S, Cs),
    phrase(tokens(Ts), Cs),
    empty_assoc(G0),
    foldl(token_screen, Ts, screen(0-0, [], false, (0-0)-[], G0, -1), Screen),
    Screen = screen(_, _, _, _, G, Last),
    (   Last >= 0
    ->  numlist(0, Last, Ys)
    ;   Ys = []
    ),
    maplist(grid_y_row(G), Ys, Rows).

grid_y_row(G, Y, Row) :-
    screen_width(W),
    W1 is W - 1,
    numlist(0, W1, Xs),
    maplist(grid_y_x_cell(G, Y), Xs, Row).

grid_y_x_cell(G, Y, X, Cell) :-
    (   get_assoc(Y-X, G, Cell)
    ->  true
    ;   empty_cell(Cell)
    ).

% Tokens: print(Char), control(Char), esc(Final), csi(Final, Groups)
% (Groups being the parameters, each a list of colon-separated numbers),
% or ignored.
tokens([T | Ts]) --> token(T), !, tokens(Ts).
tokens([]) --> [].

token(T) --> ['\e'], !, escape(T).
token(control(C)) --> [C], { control_char(C) }, !.
token(print(C)) --> [C].

% C0 controls, DEL and C1 controls.
control_char(C) :-
    char_code(C, K),
    (   K < 32
    ;   between(127, 159, K)
    ).

escape(T) --> ['['], !, csi(T).
escape(ignored) --> [C], { memberchk(C, [']', 'P', 'X', '^', '_']) }, !, string_end.
escape(esc(F)) --> intermediates, [F], { char_code(F, K), between(0x30, 0x7E, K) }, !.
escape(ignored) --> [].

% An unterminated or malformed CSI is dropped; what follows its
% introducer is read as text.
csi(T) -->
    csi_bytes(0x30, 0x3F, Ps),
    csi_bytes(0x20, 0x2F, _),
    [F],
    { char_code(F, K),
      between(0x40, 0x7E, K) }, !,
    { csi_token(Ps, F, T) }.
csi(ignored) --> [].

csi_bytes(Lo, Hi, [C | Cs]) --> [C], { char_code(C, K), between(Lo, Hi, K) }, !, csi_bytes(Lo, Hi, Cs).
csi_bytes(_, _, []) --> [].

intermediates --> [C], { char_code(C, K), between(0x20, 0x2F, K) }, !, intermediates.
intermediates --> [].

% A string (OSC, DCS, ...) ends with BEL or ST.
string_end --> ['\a'], !.
string_end --> ['\e', '\\'], !.
string_end --> ['\x9c\'], !.
string_end --> [_], !, string_end.
string_end --> [].

% Private sequences (parameters starting <, =, > or ?) are ignored. An
% empty parameter is 0.
csi_token(Ps, F, T) :-
    (   Ps = [P | _],
        memberchk(P, ['<', '=', '>', '?'])
    ->  T = ignored
    ;   string_chars(S, Ps),
        split_string(S, ";", "", Fields),
        maplist(field_group, Fields, Gs)
    ->  T = csi(F, Gs)
    ;   T = ignored
    ).

field_group(Field, G) :-
    split_string(Field, ":", "", Subs),
    maplist(sub_number, Subs, G).

sub_number("", 0) :- !.
sub_number(S, N) :-
    string_codes(S, Cs),
    forall(member(C, Cs), between(0'0, 0'9, C)),
    number_codes(N, Cs).

% screen(Cursor, Attrs, Wrap, Saved, Grid, Last)
%
%   Cursor  X-Y, 0-based
%   Attrs   the current style
%   Wrap    true if the next character goes to the next row
%   Saved   XY-Attrs, the saved position and style
%   Grid    assoc of Y-X to the cells written
%   Last    the last row that counts (see the module comment), or -1

token_screen(print(C), S0, S) :-
    S0 = screen(XY0, A, Wrap, Sv, G0, L0),
    (   Wrap == true
    ->  XY0 = _-Y0,
        Y1 is Y0 + 1,
        X-Y = 0-Y1
    ;   X-Y = XY0
    ),
    put_assoc(Y-X, G0, A-C, G),
    L is max(L0, Y),
    screen_width(W),
    (   X < W - 1
    ->  X1 is X + 1,
        S = screen(X1-Y, A, false, Sv, G, L)
    ;   S = screen(X-Y, A, true, Sv, G, L)
    ).
token_screen(control(C), S0, S) :-
    control_screen(C, S0, S).
token_screen(esc(F), S0, S) :-
    esc_screen(F, S0, S).
token_screen(csi(F, Gs), S0, S) :-
    csi_screen(F, Gs, S0, S).
token_screen(ignored, S, S).

% The cursor to X-Y, kept on the screen, with no wrap pending.
xy_screen_moved(X0-Y0, screen(_, A, _, Sv, G, L), screen(X-Y, A, false, Sv, G, L)) :-
    screen_width(W),
    X is max(0, min(W - 1, X0)),
    Y is max(0, Y0).

control_screen('\r', S0, S) :- !,
    S0 = screen(_-Y, _, _, _, _, _),
    xy_screen_moved(0-Y, S0, S).
control_screen(C, S0, S) :-
    memberchk(C, ['\n', '\v', '\f']), !,
    S0 = screen(XY, A, Wrap, Sv, G, L0),
    XY = _-Y,
    L is max(L0, Y),
    Y1 is Y + 1,
    xy_screen_moved(0-Y1, screen(XY, A, Wrap, Sv, G, L), S).
control_screen('\b', S0, S) :- !,
    S0 = screen(X-Y, _, _, _, _, _),
    X1 is X - 1,
    xy_screen_moved(X1-Y, S0, S).
control_screen('\t', S0, S) :- !,
    S0 = screen(X-Y, _, _, _, _, _),
    X1 is (X // 8 + 1) * 8,
    xy_screen_moved(X1-Y, S0, S).
control_screen(_, S, S).

esc_screen('7', screen(XY, A, Wrap, _, G, L), screen(XY, A, Wrap, XY-A, G, L)) :- !.
esc_screen('8', screen(_, _, _, Sv, G, L), S) :- !,
    Sv = XY-A,
    xy_screen_moved(XY, screen(XY, A, false, Sv, G, L), S).
esc_screen(F, S0, S) :-
    S0 = screen(X-Y, _, _, _, _, _),
    esc_move(F, X-Y, XY), !,
    xy_screen_moved(XY, S0, S).
esc_screen(_, S, S).

esc_move('D', X-Y, X-Y1) :- Y1 is Y + 1.
esc_move('E', _-Y, 0-Y1) :- Y1 is Y + 1.
esc_move('M', X-Y, X-Y1) :- Y1 is Y - 1.

csi_screen('m', Gs, screen(XY, A0, Wrap, Sv, G, L), screen(XY, A, Wrap, Sv, G, L)) :- !,
    groups_sgr(Gs, A0, A).
csi_screen('s', _, screen(XY, A, Wrap, _-SA, G, L), screen(XY, A, Wrap, XY-SA, G, L)) :- !.
csi_screen('u', _, S0, S) :- !,
    S0 = screen(_, _, _, XY-_, _, _),
    xy_screen_moved(XY, S0, S).
csi_screen(F, Gs, S0, S) :-
    S0 = screen(X-Y, _, _, _, _, _),
    csi_move(F, Gs, X-Y, XY), !,
    xy_screen_moved(XY, S0, S).
csi_screen(_, _, S, S).

csi_move('A', Gs, X-Y, X-Y1) :- groups_index_count(Gs, 0, N), Y1 is Y - N.
csi_move('B', Gs, X-Y, X-Y1) :- groups_index_count(Gs, 0, N), Y1 is Y + N.
csi_move('C', Gs, X-Y, X1-Y) :- groups_index_count(Gs, 0, N), X1 is X + N.
csi_move('D', Gs, X-Y, X1-Y) :- groups_index_count(Gs, 0, N), X1 is X - N.
csi_move('E', Gs, _-Y, 0-Y1) :- groups_index_count(Gs, 0, N), Y1 is Y + N.
csi_move('F', Gs, _-Y, 0-Y1) :- groups_index_count(Gs, 0, N), Y1 is Y - N.
csi_move('G', Gs, _-Y, X-Y) :- groups_index_count(Gs, 0, N), X is N - 1.
csi_move('`', Gs, _-Y, X-Y) :- groups_index_count(Gs, 0, N), X is N - 1.
csi_move('a', Gs, X-Y, X1-Y) :- groups_index_count(Gs, 0, N), X1 is X + N.
csi_move('d', Gs, X-_, X-Y) :- groups_index_count(Gs, 0, N), Y is N - 1.
csi_move('e', Gs, X-Y, X-Y1) :- groups_index_count(Gs, 0, N), Y1 is Y + N.
csi_move('H', Gs, _, X-Y) :- groups_row_column(Gs, X-Y).
csi_move('f', Gs, _, X-Y) :- groups_row_column(Gs, X-Y).

groups_row_column(Gs, X-Y) :-
    groups_index_count(Gs, 0, R),
    groups_index_count(Gs, 1, C),
    X is C - 1,
    Y is R - 1.

% Parameter I as a count: missing or 0 is 1.
groups_index_count(Gs, I, N) :-
    (   nth0(I, Gs, [N0 | _]),
        N0 > 0
    ->  N = N0
    ;   N = 1
    ).

% The style after SGR parameters Gs.
groups_sgr([], A, A).
groups_sgr([G | Gs0], A0, A) :-
    group_sgr(G, Gs0, Gs, A0, A1),
    groups_sgr(Gs, A1, A).

% Extended colours take their arguments from the same group (colon
% form) or from the groups that follow (semicolon form).
group_sgr([E, 5, N | _], Gs, Gs, A0, A) :-
    extended_index_attribute(E, N, Attr), !,
    attributes_with(A0, Attr, A).
group_sgr([E, 2, R, G, B], Gs, Gs, A0, A) :-
    extended_rgb_attribute(E, R, G, B, Attr), !,
    attributes_with(A0, Attr, A).
group_sgr([E, 2, _, R, G, B | _], Gs, Gs, A0, A) :-
    extended_rgb_attribute(E, R, G, B, Attr), !,
    attributes_with(A0, Attr, A).
group_sgr([E], [[5], [N | _] | Gs], Gs, A0, A) :-
    extended_index_attribute(E, N, Attr), !,
    attributes_with(A0, Attr, A).
group_sgr([E], [[2], [R | _], [G | _], [B | _] | Gs], Gs, A0, A) :-
    extended_rgb_attribute(E, R, G, B, Attr), !,
    attributes_with(A0, Attr, A).
group_sgr([4, 0], Gs, Gs, A0, A) :- !,
    attributes_without(A0, underline, A).
group_sgr([P | _], Gs, Gs, A0, A) :-
    (   parameter_sgr(P, A0, A1)
    ->  A = A1
    ;   A = A0
    ).

extended_index_attribute(38, N, fg(N)) :- between(0, 255, N).
extended_index_attribute(48, N, bg(N)) :- between(0, 255, N).

extended_rgb_attribute(38, R, G, B, fg(R, G, B)) :- maplist(between(0, 255), [R, G, B]).
extended_rgb_attribute(48, R, G, B, bg(R, G, B)) :- maplist(between(0, 255), [R, G, B]).

parameter_sgr(0, _, []).
parameter_sgr(1, A0, A) :- ord_add_element(A0, bold, A).
parameter_sgr(2, A0, A) :- ord_add_element(A0, faint, A).
parameter_sgr(3, A0, A) :- ord_add_element(A0, italic, A).
parameter_sgr(4, A0, A) :- ord_add_element(A0, underline, A).
parameter_sgr(7, A0, A) :- ord_add_element(A0, negative, A).
parameter_sgr(9, A0, A) :- ord_add_element(A0, crossed_out, A).
parameter_sgr(22, A0, A) :- ord_subtract(A0, [bold, faint], A).
parameter_sgr(23, A0, A) :- ord_del_element(A0, italic, A).
parameter_sgr(24, A0, A) :- ord_del_element(A0, underline, A).
parameter_sgr(27, A0, A) :- ord_del_element(A0, negative, A).
parameter_sgr(29, A0, A) :- ord_del_element(A0, crossed_out, A).
parameter_sgr(39, A0, A) :- attributes_with(A0, fg(default), A).
parameter_sgr(49, A0, A) :- attributes_with(A0, bg(default), A).
parameter_sgr(P, A0, A) :-
    colour_base(Colour, Base),
    P >= Base,
    P =< Base + 7,
    N is P - Base,
    colour_number(C, N),
    Attr =.. [Colour, C],
    attributes_with(A0, Attr, A).

colour_base(fg, 30).
colour_base(bg, 40).
colour_base(hfg, 90).
colour_base(hbg, 100).

colour_number(black,   0).
colour_number(red,     1).
colour_number(green,   2).
colour_number(yellow,  3).
colour_number(blue,    4).
colour_number(magenta, 5).
colour_number(cyan,    6).
colour_number(white,   7).


'#writing'.

%!  rows_string(+Rows, -Text) is det.
%
%  Text draws Rows, written as described above.
rows_string(Rows, S) :-
    phrase(rows_pieces(Rows), Pieces),
    atomic_list_concat(Pieces, A),
    atom_string(A, S).

rows_pieces([]) --> [].
rows_pieces([Row | Rows]) -->
    { row_trimmed(Row, Cells) },
    cells_pieces(Cells, []),
    rows_pieces(Rows).

% A row without its trailing empty cells.
row_trimmed(Row, Cells) :-
    reverse(Row, Rev0),
    empty_cell(E),
    list_leading_dropped(Rev0, E, Rev),
    reverse(Rev, Cells).

list_leading_dropped([X | Xs], X, Ys) :- !,
    list_leading_dropped(Xs, X, Ys).
list_leading_dropped(Xs, _, Xs).

% Cells, the style in effect being A0.
cells_pieces([], A0) -->
    (   { A0 == [] }
    ->  []
    ;   ['\e[0m']
    ),
    ['\n'].
cells_pieces([A-C | Cells], A0) -->
    (   { A == A0 }
    ->  []
    ;   sgr_piece(A)
    ),
    [C],
    cells_pieces(Cells, A).

sgr_piece([]) --> !,
    ['\e[0m'].
sgr_piece(A) -->
    { attributes_sgr(A, P),
      format(atom(E), "\e[0;~am", [P]) },
    [E].
