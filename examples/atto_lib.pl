:- module(atto_lib,
          [
            path_model/2,
            command_update_with/3,
            model_path/2,
            model_lines/2,
            model_cursor/2,
            model_top/2,
            model_modified/2,
            model_status/2,
            model_size/2,
            model_gutter_width_height/4,
            model_fits/1,
            width_line_rows/3
          ]).

/** <module> atto_lib — the editing model behind atto

Everything atto does except drawing: the document, the text cursor,
scrolling, editing, and files. Knows nothing about keys or terminals:
it is driven by commands, and describes a text area of a given size in
which lines are numbered in a gutter and wrapped.

Commands (see command_update_with/3):

  * resize(Cols, Rows)   the text area's size
  * move(Dir)            Dir: up, down, left, right, home, end, page_up,
                         page_down. Up and down move by screen row,
                         through wrapped lines.
  * point(X-Y)           the text cursor to the character at X-Y of the
                         text area (0-based, the gutter included), or as
                         near as it can go
  * scroll(Dir)          Dir: up, down. The text moves 3 rows; the text
                         cursor moves only if it would leave the area.
  * insert(Char), insert_text(Text), split_line, delete_backward,
    delete_forward, indent
  * save, revert         write the file, or reload it from disk
  * quit                 with unsaved changes, the first quit only asks
                         for confirmation (status confirm_quit)

A status is none, text(String), or confirm_quit. Any command except
resize and quit clears it.
*/


'#model'.

% atto(Path, Lines, Cursor, Top, Modified, Status, Size)
%
%   Lines     list of lines, each a list of chars
%   Cursor    L-C: 0-based line, and column within it
%   Top       first visible screen row of the text, 0-based
%   Modified  true if Lines differ from what was last loaded or saved
%   Status    none, text(String), or confirm_quit
%   Size      the text area's Cols-Rows, or unknown

%!  path_model(+Path, -Model) is det.
%
%  The model for editing the file at Path, which need not exist.
path_model(Path, atto(Path, Lines, 0-0, 0, false, Status, unknown)) :-
    path_lines_status(Path, Lines, Status).

model_path(atto(Path, _, _, _, _, _, _), Path).
model_lines(atto(_, Lines, _, _, _, _, _), Lines).
model_cursor(atto(_, _, Cursor, _, _, _, _), Cursor).
model_top(atto(_, _, _, Top, _, _, _), Top).
model_modified(atto(_, _, _, _, Mod, _, _), Mod).
model_status(atto(_, _, _, _, _, Status, _), Status).
model_size(atto(_, _, _, _, _, _, Size), Size).

path_lines_status(Path, [[]], text("New file")) :-
    \+ exists_file(Path), !.
path_lines_status(Path, Lines, none) :-
    read_file_to_string(Path, S, [encoding(utf8)]),
    string_lines(S, Lines).

string_lines(S, Lines) :-
    split_string(S, "\n", "\r", Parts0),
    (   append(Parts, [""], Parts0),
        Parts \== []
    ->  true
    ;   Parts = Parts0
    ),
    maplist(string_chars, Parts, Lines).

lines_string(Lines, S) :-
    maplist(chars_string, Lines, Strs),
    atomic_list_concat(Strs, "\n", A),
    string_concat(A, "\n", S).

chars_string(Chars, S) :-
    string_chars(S, Chars).


'#layout'.

%!  model_gutter_width_height(+Model, -Gutter, -Width, -Height) is det.
%
%  The text area: line numbers and a space take Gutter columns, text
%  wraps at Width, and Height rows are visible.
model_gutter_width_height(atto(_, Lines, _, _, _, _, Size), G, W, H) :-
    length(Lines, N),
    number_codes(N, Digits),
    length(Digits, D),
    G is D + 1,
    (   Size = Cols-Rows
    ->  W is Cols - G,
        H = Rows
    ;   W = 1000000,
        H = 1000000
    ).

%!  model_fits(+Model) is semidet.
%
%  True if the text area's size is known and has room for text.
model_fits(M) :-
    M = atto(_, _, _, _, _, _, _-_),
    model_gutter_width_height(M, _, W, H),
    W >= 1,
    H >= 1.

%!  width_line_rows(+Width, +Line, -Rows) is det.
%
%  Line, wrapped at Width, takes Rows screen rows. The position after its
%  last character always has a row.
width_line_rows(W, Line, Rows) :-
    length(Line, Len),
    Rows is Len // W + 1.

% The screen row of the text cursor, counting from the first line.
model__cursor_row(M, Row) :-
    M = atto(_, Lines, L-C, _, _, _, _),
    model_gutter_width_height(M, _, W, _),
    length(Before, L),
    append(Before, _, Lines),
    maplist(width_line_rows(W), Before, Rows),
    sum_list(Rows, R1),
    Row is R1 + C // W.

% Scroll so the text cursor is visible.
model_scrolled(M0, M) :-
    (   model_fits(M0)
    ->  M0 = atto(P, Ls, Cur, Top0, Mod, St, Sz),
        model_gutter_width_height(M0, _, _, H),
        model__cursor_row(M0, Row),
        (   Row < Top0
        ->  Top = Row
        ;   Row >= Top0 + H
        ->  Top is Row - H + 1
        ;   Top = Top0
        ),
        M = atto(P, Ls, Cur, Top, Mod, St, Sz)
    ;   M = M0
    ).


'#commands'.

%!  command_update_with(+Command, +Model0, -Next) is det.
%
%  Next is the model after Command, scrolled to keep the text cursor
%  visible, or result(quit).
command_update_with(Command, M0, Next) :-
    command_apply_with(Command, M0, Done),
    (   Done = result(_)
    ->  Next = Done
    ;   model_scrolled(Done, Next)
    ).

% Command applied, without scrolling.
command_apply_with(resize(Cols, Rows), atto(P, Ls, Cur, Top, Mod, St, _),
                   atto(P, Ls, Cur, Top, Mod, St, Cols-Rows)) :- !.
command_apply_with(quit, M, Next) :- !,
    M = atto(P, Ls, Cur, Top, Mod, St, Sz),
    (   Mod == true,
        St \== confirm_quit
    ->  Next = atto(P, Ls, Cur, Top, Mod, confirm_quit, Sz)
    ;   Next = result(quit)
    ).
command_apply_with(Command, M0, M) :-
    model__status_cleared(M0, M1),
    command_edit_with(Command, M1, M).

model__status_cleared(atto(P, Ls, Cur, Top, Mod, _, Sz), atto(P, Ls, Cur, Top, Mod, none, Sz)).

command_edit_with(save, M0, M) :- !,
    model_saved(M0, M).
command_edit_with(revert, M0, M) :- !,
    model_reverted(M0, M).
command_edit_with(move(D), M0, M) :- !,
    direction_move_by(D, M0, M).
command_edit_with(point(XY), M0, M) :- !,
    point_move_by(XY, M0, M).
command_edit_with(scroll(D), M0, M) :- !,
    direction_scroll_by(D, M0, M).
command_edit_with(insert(Ch), M0, M) :- !,
    char_insert_with(Ch, M0, M).
command_edit_with(insert_text(Text), M0, M) :- !,
    string_chars(Text, Chars),
    foldl(char_insert_with, Chars, M0, M).
command_edit_with(split_line, M0, M) :- !,
    model__line_split(M0, M).
command_edit_with(delete_backward, M0, M) :- !,
    model__deleted_backward(M0, M).
command_edit_with(delete_forward, M0, M) :- !,
    model__deleted_forward(M0, M).
command_edit_with(indent, M0, M) :-
    foldl(char_insert_with, [' ', ' ', ' ', ' '], M0, M).


'#editing'.

char_insert_with('\n', M0, M) :- !,
    model__line_split(M0, M).
char_insert_with('\t', M0, M) :- !,
    command_edit_with(indent, M0, M).
char_insert_with(Ch, M0, M) :-
    M0 = atto(P, Ls0, L-C, Top, _, St, Sz),
    nth0(L, Ls0, Line0, Rest),
    length(Before, C),
    append(Before, After, Line0),
    append(Before, [Ch | After], Line),
    nth0(L, Ls, Line, Rest),
    C1 is C + 1,
    M = atto(P, Ls, L-C1, Top, true, St, Sz).

model__line_split(atto(P, Ls0, L-C, Top, _, St, Sz), atto(P, Ls, L1-0, Top, true, St, Sz)) :-
    nth0(L, Ls0, Line, Rest0),
    length(Before, C),
    append(Before, After, Line),
    nth0(L, Rest1, Before, Rest0),
    L1 is L + 1,
    nth0(L1, Ls, After, Rest1).

model__deleted_backward(M0, M) :-
    M0 = atto(P, Ls0, L-C, Top, _, St, Sz),
    (   C > 0
    ->  C1 is C - 1,
        nth0(L, Ls0, Line0, Rest),
        nth0(C1, Line0, _, Line),
        nth0(L, Ls, Line, Rest),
        M = atto(P, Ls, L-C1, Top, true, St, Sz)
    ;   L > 0
    ->  L1 is L - 1,
        lines_index_joined_column(Ls0, L1, Ls, C1),
        M = atto(P, Ls, L1-C1, Top, true, St, Sz)
    ;   M = M0
    ).

model__deleted_forward(M0, M) :-
    M0 = atto(P, Ls0, L-C, Top, _, St, Sz),
    nth0(L, Ls0, Line0, Rest),
    length(Line0, Len),
    length(Ls0, N),
    (   C < Len
    ->  nth0(C, Line0, _, Line),
        nth0(L, Ls, Line, Rest),
        M = atto(P, Ls, L-C, Top, true, St, Sz)
    ;   L < N - 1
    ->  lines_index_joined_column(Ls0, L, Ls, _),
        M = atto(P, Ls, L-C, Top, true, St, Sz)
    ;   M = M0
    ).

% Line L joined with the line after it; C is where they meet.
lines_index_joined_column(Ls0, L, Ls, C) :-
    nth0(L, Ls0, A, Rest0),
    nth0(L, Rest0, B, Rest),
    length(A, C),
    append(A, B, AB),
    nth0(L, Ls, AB, Rest).


'#movement'.

direction_move_by(D, M0, M) :-
    M0 = atto(P, Ls, Cur0, Top, Mod, St, Sz),
    model_gutter_width_height(M0, _, W, H),
    geometry_direction_move_by(geometry(Ls, W, H), D, Cur0, Cur),
    M = atto(P, Ls, Cur, Top, Mod, St, Sz).

% The cursor L-C moved one step in direction D, in lines Ls wrapped at
% W, with H rows visible.
geometry_direction_move_by(geometry(Ls, _, _), left, L-C, Cur) :- !,
    (   C > 0
    ->  C1 is C - 1,
        Cur = L-C1
    ;   L > 0
    ->  L1 is L - 1,
        nth0(L1, Ls, Line),
        length(Line, Len),
        Cur = L1-Len
    ;   Cur = L-C
    ).
geometry_direction_move_by(geometry(Ls, _, _), right, L-C, Cur) :- !,
    nth0(L, Ls, Line),
    length(Line, Len),
    length(Ls, N),
    (   C < Len
    ->  C1 is C + 1,
        Cur = L-C1
    ;   L < N - 1
    ->  L1 is L + 1,
        Cur = L1-0
    ;   Cur = L-C
    ).
% Up and down move by screen row, through wrapped lines, keeping the
% column within the row where possible.
geometry_direction_move_by(geometry(Ls, W, _), up, L-C, Cur) :- !,
    R is C // W,
    X is C mod W,
    (   R > 0
    ->  C1 is (R - 1) * W + X,
        Cur = L-C1
    ;   L > 0
    ->  L1 is L - 1,
        nth0(L1, Ls, Line),
        length(Line, Len),
        C1 is min(Len // W * W + X, Len),
        Cur = L1-C1
    ;   Cur = L-C
    ).
geometry_direction_move_by(geometry(Ls, W, _), down, L-C, Cur) :- !,
    nth0(L, Ls, Line),
    length(Line, Len),
    length(Ls, N),
    R is C // W,
    X is C mod W,
    (   R < Len // W
    ->  C1 is min((R + 1) * W + X, Len),
        Cur = L-C1
    ;   L < N - 1
    ->  L1 is L + 1,
        nth0(L1, Ls, Next),
        length(Next, NextLen),
        C1 is min(X, NextLen),
        Cur = L1-C1
    ;   Cur = L-C
    ).
geometry_direction_move_by(_, home, L-_, L-0) :- !.
geometry_direction_move_by(geometry(Ls, _, _), end, L-_, L-Len) :- !,
    nth0(L, Ls, Line),
    length(Line, Len).
% A page is a screen less one row, moved a row at a time.
geometry_direction_move_by(Geometry, page_up, Cur0, Cur) :- !,
    geometry_direction_page(Geometry, up, Page),
    foldl(geometry_direction_move_by(Geometry), Page, Cur0, Cur).
geometry_direction_move_by(Geometry, page_down, Cur0, Cur) :-
    geometry_direction_page(Geometry, down, Page),
    foldl(geometry_direction_move_by(Geometry), Page, Cur0, Cur).

geometry_direction_page(geometry(_, _, H), D, Page) :-
    Steps is max(1, H - 1),
    length(Page, Steps),
    maplist(=(D), Page).

% The text cursor to the character at X-Y of the text area: screen row
% Top + Y, column X less the gutter. In the gutter it goes to the start
% of the row; past the end of a line, to its end; below the last line,
% to the last line.
point_move_by(X-Y, M0, M) :-
    M0 = atto(P, Ls, _, Top, Mod, St, Sz),
    model_gutter_width_height(M0, G, W, _),
    Row is Top + Y,
    Col is max(0, min(W - 1, X - G)),
    width_row_lines_position(W, Row, Ls, 0, L-R),
    nth0(L, Ls, Line),
    length(Line, Len),
    C is min(Len, R * W + Col),
    M = atto(P, Ls, L-C, Top, Mod, St, Sz).

% Screen row Row, counting from line L0 of Lines, is row R of line L
% (the last row of the last line if Row is below it).
width_row_lines_position(W, Row, [Line | Lines], L0, Pos) :-
    width_line_rows(W, Line, Rows),
    (   (   Row < Rows
        ;   Lines == []
        )
    ->  R is min(Row, Rows - 1),
        Pos = L0-R
    ;   Row1 is Row - Rows,
        L1 is L0 + 1,
        width_row_lines_position(W, Row1, Lines, L1, Pos)
    ).

% The text moved 3 rows (Top less or more, within the text), then the
% text cursor moved by rows until it is in view again.
direction_scroll_by(D, M0, M) :-
    (   model_fits(M0)
    ->  M0 = atto(P, Ls, Cur0, Top0, Mod, St, Sz),
        model_gutter_width_height(M0, _, W, H),
        maplist(width_line_rows(W), Ls, LineRows),
        sum_list(LineRows, Total),
        MaxTop is max(0, Total - H),
        direction_step(D, Step),
        Top is max(0, min(MaxTop, Top0 + Step)),
        M1 = atto(P, Ls, Cur0, Top, Mod, St, Sz),
        model__cursor_row(M1, Row),
        (   Row < Top
        ->  N is Top - Row,
            Dir = down
        ;   Row >= Top + H
        ->  N is Row - Top - H + 1,
            Dir = up
        ;   N = 0,
            Dir = down
        ),
        length(Steps, N),
        maplist(=(Dir), Steps),
        foldl(geometry_direction_move_by(geometry(Ls, W, H)), Steps, Cur0, Cur),
        M = atto(P, Ls, Cur, Top, Mod, St, Sz)
    ;   M = M0
    ).

direction_step(up, -3).
direction_step(down, 3).


'#files'.

model_saved(M0, M) :-
    M0 = atto(P, Ls, Cur, Top, Mod0, _, Sz),
    lines_string(Ls, S),
    catch(( setup_call_cleanup(open(P, write, Out, [encoding(utf8)]),
                               write(Out, S),
                               close(Out)),
            length(Ls, N),
            (   N =:= 1
            ->  Plural = ""
            ;   Plural = "s"
            ),
            format(string(Msg), "Saved ~d line~w", [N, Plural]),
            Mod = false
          ),
          E,
          ( error_message(E, Msg),
            Mod = Mod0
          )),
    M = atto(P, Ls, Cur, Top, Mod, text(Msg), Sz).

model_reverted(M0, M) :-
    M0 = atto(P, _, L0-C0, Top, _, _, Sz),
    catch(( path_lines_status(P, Ls, _),
            St = text("Reverted to file on disk")
          ),
          E,
          ( M0 = atto(_, Ls, _, _, _, _, _),
            error_message(E, Msg),
            St = text(Msg)
          )),
    length(Ls, N),
    L is min(L0, N - 1),
    nth0(L, Ls, Line),
    length(Line, Len),
    C is min(C0, Len),
    M = atto(P, Ls, L-C, Top, false, St, Sz).

error_message(E, Msg) :-
    format(string(Msg), "Error: ~q", [E]).
