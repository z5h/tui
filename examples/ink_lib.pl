:- module(ink_lib,
          [
            path_model/2,
            command_update_with/3,
            model_path/2,
            model_rows/2,
            model_cursor/2,
            model_top/2,
            model_modified/2,
            model_status/2,
            model_size/2,
            model_selection/2,
            model_fits/1,
            model_gutter/2
          ]).

/** <module> ink_lib — the editing model behind ink

Everything ink does except drawing: a screen of styled cells (see
sgr_screen_lib.pl), the cursor on it, a rectangular selection, a
clipboard, scrolling, editing, and files. Knows nothing about keys or
terminals: it is driven by commands, and describes a canvas area of a
given size, in which rows are numbered in a gutter if there is room for
it.

Rows are always 80 cells wide. Typing overwrites; a typed character
keeps the style of the cell it lands on. There is at least one row.

There is always a selection: the rectangle from the anchor to the
cursor, both included. Collapsing it puts the anchor on the cursor, so
the selection is the cursor's cell.

Commands (see command_update_with/3):

  * resize(Cols, Rows)   the canvas area's size
  * move(Dir)            Dir: up, down, left, right, home, end, page_up,
                         page_down, tab. Collapses the selection. End is
                         after the last cell that is not empty.
  * extend(Dir)          as move(Dir), but the anchor stays
  * point(X-Y)           the cursor to the cell at X-Y of the canvas area
                         (0-based, the gutter included), or as near as
                         it can go; collapses the selection
  * extend_to(X-Y)       as point(X-Y), but the anchor stays
  * escape               collapses the selection, and clears the status
  * scroll(Dir)          Dir: up, down. The rows move 3; the cursor only
                         if it would leave the area.
  * type(Char)           Char overwrites the cell under the cursor, which
                         then moves right (not past the last column)
  * type_text(Text)      as typing each char; a line break goes to the
                         next row (added if need be), at the column the
                         text started at
  * return               the cursor to the start of the next row, if
                         there is one
  * new_line             an empty row after the cursor's, and the cursor
                         to its start
  * delete_line          the cursor's row removed
  * erase                the char of the selected cells becomes a space;
                         the style stays
  * erase_backward       erase, but if the selection is collapsed the
                         cursor first moves left
  * style(Op)            the selected cells: Op is
                         toggle(Attr) (removed from all if all have it,
                         else added to all), set(Attr) (see
                         attributes_with/3), or plain (no style)
  * copy                 the selected cells, style and all, to the
                         clipboard
  * cut                  copy, then the selected cells become empty; the
                         selection collapses on its top-left cell, so a
                         paste puts them back
  * paste                the clipboard's cells overwrite those from the
                         cursor right and down, as far as the last
                         column; rows are added below if need be. The
                         selection collapses.
  * ask(Kind)            Kind: fg, bg. Only sets the status, for the
                         app to ask which colour.
  * save                 write the file
  * revert, quit         reload the file from disk, or end. With unsaved
                         changes, the first only asks for confirmation
                         (status confirm(revert) or confirm(quit)).

A status is none, text(String), confirm(Command) or ask(Kind). Any
command except resize and ask clears it, unless it sets it.
*/

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(sgr_screen_lib).


'#model'.

% ink(Path, Rows, Cursor, Anchor, Top, Modified, Status, Size, Clipboard)
%
%   Rows       the screen, a list of rows of cells Attrs-Char
%   Cursor     X-Y, 0-based, on the screen
%   Anchor     the selection's corner opposite the cursor, X-Y
%   Top        the first visible row, 0-based
%   Modified   true if Rows differ from what was last loaded or saved
%   Status     none, text(String), confirm(Command) or ask(Kind)
%   Size       the canvas area's Cols-Rows, or unknown
%   Clipboard  none, or a rectangle of cells: a list of equally long
%              rows of cells

%!  path_model(+Path, -Model) is det.
%
%  The model for editing the file at Path, which need not exist.
path_model(Path, ink(Path, Rows, 0-0, 0-0, 0, false, Status, unknown, none)) :-
    path_rows_status(Path, Rows, Status).

%!  model_path(+Model, -Path) is det.
%!  model_rows(+Model, -Rows) is det.
%!  model_cursor(+Model, -Cursor) is det.
%!  model_top(+Model, -Top) is det.
%!  model_modified(+Model, -Modified) is det.
%!  model_status(+Model, -Status) is det.
%!  model_size(+Model, -Size) is det.
%
%  The parts of Model, as described above.
model_path(ink(Path, _, _, _, _, _, _, _, _), Path).
model_rows(ink(_, Rows, _, _, _, _, _, _, _), Rows).
model_cursor(ink(_, _, Cursor, _, _, _, _, _, _), Cursor).
model_top(ink(_, _, _, _, Top, _, _, _, _), Top).
model_modified(ink(_, _, _, _, _, Mod, _, _, _), Mod).
model_status(ink(_, _, _, _, _, _, Status, _, _), Status).
model_size(ink(_, _, _, _, _, _, _, Size, _), Size).

%!  model_selection(+Model, -Selection) is det.
%
%  Selection is rect(X0-Y0, X1-Y1): the selected cells are those in
%  columns X0..X1 of rows Y0..Y1.
model_selection(ink(_, _, CX-CY, AX-AY, _, _, _, _, _), rect(X0-Y0, X1-Y1)) :-
    X0 is min(CX, AX),
    X1 is max(CX, AX),
    Y0 is min(CY, AY),
    Y1 is max(CY, AY).

%!  model_fits(+Model) is semidet.
%
%  True if the canvas area's size is known and has room for a row.
model_fits(M) :-
    model_size(M, Cols-Rows),
    screen_width(W),
    Cols >= W,
    Rows >= 1.

%!  model_gutter(+Model, -Gutter) is det.
%
%  Row numbers and a space take the Gutter columns left of the rows: as
%  many as the last row's number needs, plus one, if the canvas area has
%  room for them beside the rows, else 0.
model_gutter(M, G) :-
    model_rows(M, Rows),
    length(Rows, N),
    number_codes(N, Digits),
    length(Digits, D),
    G0 is D + 1,
    screen_width(W),
    (   model_size(M, Cols-_),
        Cols >= W + G0
    ->  G = G0
    ;   G = 0
    ).

path_rows_status(Path, [Row], text("New file")) :-
    \+ exists_file(Path), !,
    empty_row(Row).
path_rows_status(Path, Rows, none) :-
    read_file_to_string(Path, S, [encoding(utf8)]),
    string_rows(S, Rows0),
    (   Rows0 == []
    ->  empty_row(Row),
        Rows = [Row]
    ;   Rows = Rows0
    ).

empty_row(Row) :-
    screen_width(W),
    empty_cell(E),
    length(Row, W),
    maplist(=(E), Row).


'#commands'.

%!  command_update_with(+Command, +Model0, -Next) is det.
%
%  Next is the model after Command, scrolled to keep the cursor
%  visible, or result(quit).
command_update_with(Command, M0, Next) :-
    command_apply_with(Command, M0, Done),
    (   Done = result(_)
    ->  Next = Done
    ;   model_scrolled(Done, Next)
    ).

% Command applied, without scrolling.
command_apply_with(resize(Cols, Rows), ink(P, Rs, Cur, An, Top, Mod, St, _, Cb),
                   ink(P, Rs, Cur, An, Top, Mod, St, Cols-Rows, Cb)) :- !.
command_apply_with(ask(Kind), ink(P, Rs, Cur, An, Top, Mod, _, Sz, Cb),
                   ink(P, Rs, Cur, An, Top, Mod, ask(Kind), Sz, Cb)) :- !.
% Revert and quit lose unsaved changes, so they first ask.
command_apply_with(Command, M0, M) :-
    memberchk(Command, [revert, quit]), !,
    M0 = ink(P, Rs, Cur, An, Top, Mod, St, Sz, Cb),
    (   Mod == true,
        St \== confirm(Command)
    ->  M = ink(P, Rs, Cur, An, Top, Mod, confirm(Command), Sz, Cb)
    ;   Command == quit
    ->  M = result(quit)
    ;   model_reverted(M0, M)
    ).
command_apply_with(Command, M0, M) :-
    model_status_none(M0, M1),
    command_edit_with(Command, M1, M).

model_status_none(ink(P, Rs, Cur, An, Top, Mod, _, Sz, Cb), ink(P, Rs, Cur, An, Top, Mod, none, Sz, Cb)).

command_edit_with(save, M0, M) :- !,
    model_saved(M0, M).
command_edit_with(move(D), M0, M) :- !,
    direction_moved(D, M0, M1),
    model_collapsed(M1, M).
command_edit_with(extend(D), M0, M) :- !,
    direction_moved(D, M0, M).
command_edit_with(point(XY), M0, M) :- !,
    model_area_point_cursor(M0, XY, Cur),
    model_cursor_set(M0, Cur, M1),
    model_collapsed(M1, M).
command_edit_with(extend_to(XY), M0, M) :- !,
    model_area_point_cursor(M0, XY, Cur),
    model_cursor_set(M0, Cur, M).
command_edit_with(escape, M0, M) :- !,
    model_collapsed(M0, M).
command_edit_with(scroll(D), M0, M) :- !,
    direction_scrolled(D, M0, M).
command_edit_with(type(Ch), M0, M) :- !,
    char_typed(Ch, M0, M1),
    model_collapsed(M1, M).
command_edit_with(type_text(Text), M0, M) :- !,
    model_cursor(M0, X-_),
    string_chars(Text, Chars),
    foldl(column_char_typed(X), Chars, M0, M1),
    model_collapsed(M1, M).
command_edit_with(return, M0, M) :- !,
    M0 = ink(P, Rs, _-Y, An, Top, Mod, St, Sz, Cb),
    length(Rs, N),
    (   Y < N - 1
    ->  Y1 is Y + 1,
        model_collapsed(ink(P, Rs, 0-Y1, An, Top, Mod, St, Sz, Cb), M)
    ;   M = M0
    ).
command_edit_with(new_line, ink(P, Rs0, _-Y, An, Top, _, St, Sz, Cb), M) :- !,
    Y1 is Y + 1,
    empty_row(E),
    nth0(Y1, Rs, E, Rs0),
    model_collapsed(ink(P, Rs, 0-Y1, An, Top, true, St, Sz, Cb), M).
command_edit_with(delete_line, ink(P, Rs0, X-Y, An, Top, _, St, Sz, Cb), M) :- !,
    nth0(Y, Rs0, _, Rs1),
    (   Rs1 == []
    ->  empty_row(E),
        Rs = [E]
    ;   Rs = Rs1
    ),
    length(Rs, N),
    Y1 is min(Y, N - 1),
    model_collapsed(ink(P, Rs, X-Y1, An, Top, true, St, Sz, Cb), M).
command_edit_with(erase, M0, M) :- !,
    model_cells_mapped(M0, cell_erased, M).
command_edit_with(erase_backward, M0, M) :- !,
    M0 = ink(_, _, X-Y, An, _, _, _, _, _),
    (   An == X-Y
    ->  X1 is max(0, X - 1),
        model_cursor_set(M0, X1-Y, M1),
        model_collapsed(M1, M2),
        model_cells_mapped(M2, cell_erased, M)
    ;   model_cells_mapped(M0, cell_erased, M)
    ).
command_edit_with(style(Op), M0, M) :- !,
    model_selection(M0, Rect),
    model_rows(M0, Rs),
    style_rows_rect_goal(Op, Rs, Rect, Goal),
    model_cells_mapped(M0, Goal, M).
command_edit_with(copy, M0, M) :- !,
    model_copied(M0, M).
command_edit_with(cut, M0, M) :- !,
    model_copied(M0, M1),
    model_cells_mapped(M1, cell_emptied, M2),
    model_selection(M2, rect(TopLeft, _)),
    model_cursor_set(M2, TopLeft, M3),
    model_collapsed(M3, M).
command_edit_with(paste, M0, M) :-
    model_pasted(M0, M1),
    model_collapsed(M1, M).

% The selection collapsed: the anchor on the cursor.
model_collapsed(ink(P, Rs, Cur, _, Top, Mod, St, Sz, Cb), ink(P, Rs, Cur, Cur, Top, Mod, St, Sz, Cb)).

model_cursor_set(ink(P, Rs, _, An, Top, Mod, St, Sz, Cb), Cur, ink(P, Rs, Cur, An, Top, Mod, St, Sz, Cb)).


'#editing'.

% Goal maps the selected cells of M; the model is then modified.
model_cells_mapped(M0, Goal, M) :-
    M0 = ink(P, Rs0, Cur, An, Top, _, St, Sz, Cb),
    model_selection(M0, Rect),
    rows_rect_mapped(Rs0, Rect, Goal, Rs),
    M = ink(P, Rs, Cur, An, Top, true, St, Sz, Cb).

rows_rect_mapped(Rs0, Rect, Goal, Rs) :-
    foldl(row_mapped(Rect, Goal), Rs0, Rs, 0, _).

row_mapped(rect(X0-Y0, X1-Y1), Goal, R0, R, Y, Yn) :-
    Yn is Y + 1,
    (   between(Y0, Y1, Y)
    ->  foldl(cell_mapped(X0-X1, Goal), R0, R, 0, _)
    ;   R = R0
    ).

cell_mapped(X0-X1, Goal, C0, C, X, Xn) :-
    Xn is X + 1,
    (   between(X0, X1, X)
    ->  call(Goal, C0, C)
    ;   C = C0
    ).

cell_erased(A-_, A-' ').

cell_emptied(_, E) :-
    empty_cell(E).

% The goal applying style Op to the cells of Rect in Rs.
style_rows_rect_goal(toggle(Attr), Rs, Rect, Goal) :-
    rows_rect_cells(Rs, Rect, Cells),
    (   forall(member(A-_, Cells), memberchk(Attr, A))
    ->  Goal = cell_attribute_removed(Attr)
    ;   Goal = cell_attribute_set(Attr)
    ).
style_rows_rect_goal(set(Attr), _, _, cell_attribute_set(Attr)).
style_rows_rect_goal(plain, _, _, cell_plain).

rows_rect_cells(Rs, rect(X0-Y0, X1-Y1), Cells) :-
    findall(Cell,
            ( between(Y0, Y1, Y),
              nth0(Y, Rs, R),
              between(X0, X1, X),
              nth0(X, R, Cell)
            ),
            Cells).

cell_attribute_set(Attr, A0-C, A-C) :-
    attributes_with(A0, Attr, A).

cell_attribute_removed(Attr, A0-C, A-C) :-
    attributes_without(A0, Attr, A).

cell_plain(_-C, []-C).

% Ch overwrites the cursor's cell, keeping its style; the cursor moves
% right, but not past the last column.
char_typed(Ch, ink(P, Rs0, X-Y, An, Top, _, St, Sz, Cb), ink(P, Rs, X1-Y, An, Top, true, St, Sz, Cb)) :-
    rows_xy_mapped(Rs0, X-Y, cell_char_set(Ch), Rs),
    screen_width(W),
    X1 is min(W - 1, X + 1).

cell_char_set(Ch, A-_, A-Ch).

rows_xy_mapped(Rs0, X-Y, Goal, Rs) :-
    nth0(Y, Rs0, R0, Rest),
    nth0(X, R0, C0, RRest),
    call(Goal, C0, C),
    nth0(X, R, C, RRest),
    nth0(Y, Rs, R, Rest).

% Pasted text: a line break goes to column X0 of the next row, added if
% need be; a tab is a space; other controls are dropped.
column_char_typed(X0, '\n', ink(P, Rs0, _-Y, An, Top, Mod, St, Sz, Cb), M) :- !,
    Y1 is Y + 1,
    rows_count_extended(Rs0, Y1 + 1, Rs),
    M = ink(P, Rs, X0-Y1, An, Top, Mod, St, Sz, Cb).
column_char_typed(X0, '\t', M0, M) :- !,
    column_char_typed(X0, ' ', M0, M).
column_char_typed(_, Ch, M0, M) :-
    (   char_type(Ch, cntrl)
    ->  M = M0
    ;   char_typed(Ch, M0, M)
    ).

% Rows, with empty rows added below Rs0 to make at least N.
rows_count_extended(Rs0, N0, Rs) :-
    N is N0,
    length(Rs0, L),
    (   L >= N
    ->  Rs = Rs0
    ;   Add is N - L,
        empty_row(E),
        length(Es, Add),
        maplist(=(E), Es),
        append(Rs0, Es, Rs)
    ).


'#clipboard'.

model_copied(M0, M) :-
    M0 = ink(P, Rs, Cur, An, Top, Mod, _, Sz, _),
    model_selection(M0, rect(X0-Y0, X1-Y1)),
    W is X1 - X0 + 1,
    H is Y1 - Y0 + 1,
    length(Above, Y0),
    length(Selected, H),
    append(Above, Rest, Rs),
    append(Selected, _, Rest),
    maplist(row_from_count_cells(X0, W), Selected, Cb),
    format(string(Msg), "Copied ~d×~d", [W, H]),
    M = ink(P, Rs, Cur, An, Top, Mod, text(Msg), Sz, Cb).

row_from_count_cells(X0, W, Row, Cells) :-
    length(Before, X0),
    length(Cells, W),
    append(Before, Rest, Row),
    append(Cells, _, Rest).

% The clipboard's rows overwrite from the cursor, each cut at the last
% column; rows are added below to make room.
model_pasted(M0, M) :-
    M0 = ink(P, Rs0, X-Y, An, Top, Mod, St, Sz, Cb),
    (   Cb == none
    ->  M = ink(P, Rs0, X-Y, An, Top, Mod, text("Nothing to paste"), Sz, Cb)
    ;   length(Cb, H),
        rows_count_extended(Rs0, Y + H, Rs1),
        foldl(column_row_pasted(X), Cb, Y-Rs1, _-Rs),
        M = ink(P, Rs, X-Y, An, Top, true, St, Sz, Cb)
    ).

column_row_pasted(X, Cells, Y-Rs0, Y1-Rs) :-
    Y1 is Y + 1,
    nth0(Y, Rs0, Row0, Rest),
    screen_width(W),
    Fits is W - X,
    (   length(Shown, Fits),
        append(Shown, _, Cells)
    ->  true
    ;   Shown = Cells
    ),
    length(Shown, Len),
    length(Before, X),
    length(Covered, Len),
    append(Before, Rest0, Row0),
    append(Covered, After, Rest0),
    append([Before, Shown, After], Row),
    nth0(Y, Rs, Row, Rest).


'#movement'.

direction_moved(D, M0, M) :-
    M0 = ink(P, Rs, Cur0, An, Top, Mod, St, Sz, Cb),
    model_height(M0, H),
    length(Rs, N),
    rows_count_height_direction_moved(Rs, N, H, D, Cur0, Cur),
    M = ink(P, Rs, Cur, An, Top, Mod, St, Sz, Cb).

rows_count_height_direction_moved(Rs, N, H, D, X0-Y0, X-Y) :-
    screen_width(W),
    (   D == up        -> X1 = X0, Y1 is Y0 - 1
    ;   D == down      -> X1 = X0, Y1 is Y0 + 1
    ;   D == left      -> X1 is X0 - 1, Y1 = Y0
    ;   D == right     -> X1 is X0 + 1, Y1 = Y0
    ;   D == home      -> X1 = 0, Y1 = Y0
    ;   D == end       -> nth0(Y0, Rs, R), row_end(R, X1), Y1 = Y0
    ;   D == page_up   -> X1 = X0, Y1 is Y0 - max(1, H - 1)
    ;   D == page_down -> X1 = X0, Y1 is Y0 + max(1, H - 1)
    ;   D == tab       -> X1 is (X0 // 8 + 1) * 8, Y1 = Y0
    ;   X1 = X0, Y1 = Y0
    ),
    X is max(0, min(W - 1, X1)),
    Y is max(0, min(N - 1, Y1)).

% The column after the last cell that is not empty.
row_end(R, X) :-
    empty_cell(E),
    reverse(R, Rev),
    (   nth0(I, Rev, C),
        C \== E
    ->  length(R, W),
        X is W - I
    ;   X = 0
    ).

% The cursor for X-Y of the canvas area: row Top + Y, column X less the
% gutter.
model_area_point_cursor(M, X0-Y0, X-Y) :-
    model_rows(M, Rs),
    model_top(M, Top),
    model_gutter(M, G),
    length(Rs, N),
    screen_width(W),
    X is max(0, min(W - 1, X0 - G)),
    Y is max(0, min(N - 1, Top + Y0)).

model_height(M, H) :-
    (   model_size(M, _-H0)
    ->  H = H0
    ;   H = 1000000
    ).

% Scroll so the cursor is visible.
model_scrolled(M0, M) :-
    (   model_fits(M0)
    ->  M0 = ink(P, Rs, X-Y, An, Top0, Mod, St, Sz, Cb),
        model_height(M0, H),
        (   Y < Top0
        ->  Top = Y
        ;   Y >= Top0 + H
        ->  Top is Y - H + 1
        ;   Top = Top0
        ),
        M = ink(P, Rs, X-Y, An, Top, Mod, St, Sz, Cb)
    ;   M = M0
    ).

% The rows move 3 (within the screen), then the cursor into view. A
% collapsed selection stays collapsed.
direction_scrolled(D, M0, M) :-
    (   model_fits(M0)
    ->  M0 = ink(P, Rs, X-Y0, An0, Top0, Mod, St, Sz, Cb),
        model_height(M0, H),
        length(Rs, N),
        MaxTop is max(0, N - H),
        direction_step(D, Step),
        Top is max(0, min(MaxTop, Top0 + Step)),
        Y is max(Top, min(Top + H - 1, Y0)),
        (   An0 == X-Y0
        ->  An = X-Y
        ;   An = An0
        ),
        M = ink(P, Rs, X-Y, An, Top, Mod, St, Sz, Cb)
    ;   M = M0
    ).

direction_step(up, -3).
direction_step(down, 3).


'#files'.

model_saved(M0, M) :-
    M0 = ink(P, Rs, Cur, An, Top, Mod0, _, Sz, Cb),
    rows_string(Rs, S),
    catch(( setup_call_cleanup(open(P, write, Out, [encoding(utf8)]),
                               write(Out, S),
                               close(Out)),
            length(Rs, N),
            (   N =:= 1
            ->  Plural = ""
            ;   Plural = "s"
            ),
            format(string(Msg), "Saved ~d row~w", [N, Plural]),
            Mod = false
          ),
          E,
          ( error_message(E, Msg),
            Mod = Mod0
          )),
    M = ink(P, Rs, Cur, An, Top, Mod, text(Msg), Sz, Cb).

% The file reloaded; the clipboard is kept.
model_reverted(M0, M) :-
    M0 = ink(P, _, X-Y0, _, Top, _, _, Sz, Cb),
    catch(( path_rows_status(P, Rs, _),
            St = text("Reverted to file on disk")
          ),
          E,
          ( M0 = ink(_, Rs, _, _, _, _, _, _, _),
            error_message(E, Msg),
            St = text(Msg)
          )),
    length(Rs, N),
    Y is min(Y0, N - 1),
    M = ink(P, Rs, X-Y, X-Y, Top, false, St, Sz, Cb).

error_message(E, Msg) :-
    format(string(Msg), "Error: ~q", [E]).
