:- module(atto_lib,
          [
            path_model/2,
            model_command_next/3,
            model_path/2,
            model_lines/2,
            model_cursor/2,
            model_top/2,
            model_modified/2,
            model_status/2,
            model_size/2,
            model_layout/4,
            model_fits/1
          ]).

/** <module> atto_lib — the editing model behind atto

Everything atto does except drawing: the document, the text cursor,
scrolling, editing, and files. Knows nothing about keys or terminals:
it is driven by commands, and describes a text area of a given size in
which lines are numbered in a gutter and wrapped.

Commands (see model_command_next/3):

  * resize(Cols, Rows)   the text area's size
  * move(Dir)            Dir: up, down, left, right, home, end, page_up,
                         page_down. Up and down move by screen row,
                         through wrapped lines.
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

%!  model_layout(+Model, -Gutter, -Width, -Height) is det.
%
%  The text area: line numbers and a space take Gutter columns, text
%  wraps at Width, and Height rows are visible.
model_layout(atto(_, Lines, _, _, _, _, Size), G, W, H) :-
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
    model_layout(M, _, W, H),
    W >= 1,
    H >= 1.

line_rows(W, Line, Rows) :-
    length(Line, Len),
    Rows is Len // W + 1.

% The screen row of the text cursor, counting from the first line.
model_cursor_row(M, Row) :-
    M = atto(_, Lines, L-C, _, _, _, _),
    model_layout(M, _, W, _),
    length(Before, L),
    append(Before, _, Lines),
    foldl(rows_added(W), Before, 0, R1),
    Row is R1 + C // W.

rows_added(W, Line, R0, R) :-
    line_rows(W, Line, N),
    R is R0 + N.

% Scroll so the text cursor is visible.
model_scrolled(M0, M) :-
    (   model_fits(M0)
    ->  M0 = atto(P, Ls, Cur, Top0, Mod, St, Sz),
        model_layout(M0, _, _, H),
        model_cursor_row(M0, Row),
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

%!  model_command_next(+Command, +Model0, -Next) is det.
%
%  Next is the model after Command, scrolled to keep the text cursor
%  visible, or result(quit).
model_command_next(Command, M0, Next) :-
    command_update_with(Command, M0, Done),
    (   Done = result(_)
    ->  Next = Done
    ;   model_scrolled(Done, Next)
    ).

command_update_with(resize(Cols, Rows), atto(P, Ls, Cur, Top, Mod, St, _),
                    atto(P, Ls, Cur, Top, Mod, St, Cols-Rows)) :- !.
command_update_with(quit, M, Next) :- !,
    M = atto(P, Ls, Cur, Top, Mod, St, Sz),
    (   Mod == true,
        St \== confirm_quit
    ->  Next = atto(P, Ls, Cur, Top, Mod, confirm_quit, Sz)
    ;   Next = result(quit)
    ).
command_update_with(Command, M0, M) :-
    model_status_cleared(M0, M1),
    model_command_edited(Command, M1, M).

model_status_cleared(atto(P, Ls, Cur, Top, Mod, _, Sz), atto(P, Ls, Cur, Top, Mod, none, Sz)).

model_command_edited(save, M0, M) :- !,
    model_saved(M0, M).
model_command_edited(revert, M0, M) :- !,
    model_reverted(M0, M).
model_command_edited(move(D), M0, M) :- !,
    model_direction_moved(M0, D, M).
model_command_edited(insert(Ch), M0, M) :- !,
    char_inserted(Ch, M0, M).
model_command_edited(insert_text(Text), M0, M) :- !,
    string_chars(Text, Chars),
    foldl(char_inserted, Chars, M0, M).
model_command_edited(split_line, M0, M) :- !,
    model_line_split(M0, M).
model_command_edited(delete_backward, M0, M) :- !,
    model_deleted_backward(M0, M).
model_command_edited(delete_forward, M0, M) :- !,
    model_deleted_forward(M0, M).
model_command_edited(indent, M0, M) :-
    foldl(char_inserted, [' ', ' ', ' ', ' '], M0, M).


'#editing'.

char_inserted('\n', M0, M) :- !,
    model_line_split(M0, M).
char_inserted('\t', M0, M) :- !,
    model_command_edited(indent, M0, M).
char_inserted(Ch, M0, M) :-
    M0 = atto(P, Ls0, L-C, Top, _, St, Sz),
    nth0(L, Ls0, Line0, Rest),
    length(Before, C),
    append(Before, After, Line0),
    append(Before, [Ch | After], Line),
    nth0(L, Ls, Line, Rest),
    C1 is C + 1,
    M = atto(P, Ls, L-C1, Top, true, St, Sz).

model_line_split(atto(P, Ls0, L-C, Top, _, St, Sz), atto(P, Ls, L1-0, Top, true, St, Sz)) :-
    nth0(L, Ls0, Line, Rest0),
    length(Before, C),
    append(Before, After, Line),
    nth0(L, Rest1, Before, Rest0),
    L1 is L + 1,
    nth0(L1, Ls, After, Rest1).

model_deleted_backward(M0, M) :-
    M0 = atto(P, Ls0, L-C, Top, _, St, Sz),
    (   C > 0
    ->  C1 is C - 1,
        nth0(L, Ls0, Line0, Rest),
        nth0(C1, Line0, _, Line),
        nth0(L, Ls, Line, Rest),
        M = atto(P, Ls, L-C1, Top, true, St, Sz)
    ;   L > 0
    ->  L1 is L - 1,
        lines_joined(Ls0, L1, Ls, C1),
        M = atto(P, Ls, L1-C1, Top, true, St, Sz)
    ;   M = M0
    ).

model_deleted_forward(M0, M) :-
    M0 = atto(P, Ls0, L-C, Top, _, St, Sz),
    nth0(L, Ls0, Line0, Rest),
    length(Line0, Len),
    length(Ls0, N),
    (   C < Len
    ->  nth0(C, Line0, _, Line),
        nth0(L, Ls, Line, Rest),
        M = atto(P, Ls, L-C, Top, true, St, Sz)
    ;   L < N - 1
    ->  lines_joined(Ls0, L, Ls, _),
        M = atto(P, Ls, L-C, Top, true, St, Sz)
    ;   M = M0
    ).

% Line L joined with the line after it; C is where they meet.
lines_joined(Ls0, L, Ls, C) :-
    nth0(L, Ls0, A, Rest0),
    nth0(L, Rest0, B, Rest),
    length(A, C),
    append(A, B, AB),
    nth0(L, Ls, AB, Rest).


'#movement'.

model_direction_moved(M0, D, M) :-
    M0 = atto(P, Ls, Cur0, Top, Mod, St, Sz),
    model_layout(M0, _, W, H),
    lines_width_height_direction_cursor(Ls, W, H, D, Cur0, Cur),
    M = atto(P, Ls, Cur, Top, Mod, St, Sz).

lines_width_height_direction_cursor(Ls, _, _, left, L-C, Cur) :- !,
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
lines_width_height_direction_cursor(Ls, _, _, right, L-C, Cur) :- !,
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
lines_width_height_direction_cursor(Ls, W, _, up, L-C, Cur) :- !,
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
lines_width_height_direction_cursor(Ls, W, _, down, L-C, Cur) :- !,
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
lines_width_height_direction_cursor(_, _, _, home, L-_, L-0) :- !.
lines_width_height_direction_cursor(Ls, _, _, end, L-_, L-Len) :- !,
    nth0(L, Ls, Line),
    length(Line, Len).
lines_width_height_direction_cursor(Ls, W, H, page_up, Cur0, Cur) :- !,
    Steps is max(1, H - 1),
    numlist(1, Steps, Ns),
    foldl(step_moved(Ls, W, H, up), Ns, Cur0, Cur).
lines_width_height_direction_cursor(Ls, W, H, page_down, Cur0, Cur) :-
    Steps is max(1, H - 1),
    numlist(1, Steps, Ns),
    foldl(step_moved(Ls, W, H, down), Ns, Cur0, Cur).

step_moved(Ls, W, H, D, _, Cur0, Cur) :-
    lines_width_height_direction_cursor(Ls, W, H, D, Cur0, Cur).


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
