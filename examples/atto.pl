:- module(atto, [atto/1]).

/** <module> atto — a tiny text editor

    swipl -p library=prolog examples/atto.pl FILE

Edits FILE, which need not exist yet. Lines wrap to the screen width and
are numbered. ^S saves, ^R reverts to the file on disk, ^Q quits (twice
if there are unsaved changes). No undo.

The text cursor is the framework's cursor: after every update the screen
cursor is placed where the text cursor is drawn, and the editor area
claims the arrow keys so the framework does not move it.
*/

:- use_module(library(tui)).
:- use_module(library(tui/utils)).

:- multifile tui:alias_drawable/2.
:- multifile tui:at_event_is/3.

:- initialization(main, main).

main :-
    current_prolog_flag(argv, Argv),
    (   Argv = [Path]
    ->  atto(Path)
    ;   format(user_error, "usage: atto FILE~n", []),
        halt(1)
    ).

atto(Path) :-
    path_model(Path, Model),
    app((1-1)-Model, view, update, _).


'#model'.

% atto(Path, Lines, Cursor, Top, Modified, Status, Size)
%
%   Lines     list of lines, each a list of chars
%   Cursor    L-C: 0-based line, and column within it
%   Top       first visible screen row of the text, 0-based
%   Modified  true if Lines differ from what was last loaded or saved
%   Status    none, text(String), or confirm_quit
%   Size      Cols-Rows, or unknown before the first terminal_size

path_model(Path, atto(Path, Lines, 0-0, 0, false, Status, unknown)) :-
    path_lines_status(Path, Lines, Status).

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

% Gutter width G (line numbers and a space), text width W, text height H.
% The text area lies between the title row and the status and menu rows.
model_layout(atto(_, Lines, _, _, _, _, Size), G, W, H) :-
    length(Lines, N),
    number_codes(N, Digits),
    length(Digits, D),
    G is D + 1,
    (   Size = Cols-Rows
    ->  W is Cols - G,
        H is Rows - 3
    ;   W = 1000000,
        H = 1000000
    ).

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

% The app state: the screen cursor on the text cursor.
model_state(M, (X-Y)-M) :-
    (   model_fits(M)
    ->  M = atto(_, _, _-C, Top, _, _, _),
        model_layout(M, G, W, _),
        model_cursor_row(M, Row),
        X is G + 1 + C mod W,
        Y is 2 + Row - Top
    ;   X-Y = 1-1
    ).


'#update'.

:- det(update/3).
update(E, (_-_)-M0, S) :-
    model_event_next(E, M0, Next),
    (   Next = result(R)
    ->  S = result(R)
    ;   model_scrolled(Next, M),
        model_state(M, S)
    ).

model_event_next(terminal_size(Cols, Rows), atto(P, Ls, Cur, Top, Mod, St, _),
                 atto(P, Ls, Cur, Top, Mod, St, Cols-Rows)) :- !.
model_event_next(ctrl+q, M, Next) :- !,
    M = atto(P, Ls, Cur, Top, Mod, St, Sz),
    (   Mod == true,
        St \== confirm_quit
    ->  Next = atto(P, Ls, Cur, Top, Mod, confirm_quit, Sz)
    ;   Next = result(quit)
    ).
model_event_next(E, M0, M) :-
    model_status(M0, none, M1),
    model_event_handled(E, M1, M).

model_status(atto(P, Ls, Cur, Top, Mod, _, Sz), St, atto(P, Ls, Cur, Top, Mod, St, Sz)).

model_event_handled(ctrl+s, M0, M) :- !,
    model_saved(M0, M).
model_event_handled(ctrl+r, M0, M) :- !,
    model_reverted(M0, M).
model_event_handled(cursor(D), M0, M) :- !,
    model_direction_moved(M0, D, M).
model_event_handled(E, M0, M) :-
    memberchk(E, [home, end, page_up, page_down]), !,
    model_direction_moved(M0, E, M).
model_event_handled(paste(Text), M0, M) :- !,
    string_chars(Text, Chars),
    foldl(char_inserted, Chars, M0, M).
model_event_handled(E, M0, M) :-
    memberchk(E, [return, backspace, delete, tab]), !,
    model_key_edited(M0, E, M).
model_event_handled(E, M0, M) :-
    atom(E),
    atom_length(E, 1),
    \+ char_type(E, cntrl), !,
    char_inserted(E, M0, M).
model_event_handled(_, M, M).

char_inserted('\n', M0, M) :- !,
    model_key_edited(M0, return, M).
char_inserted('\t', M0, M) :- !,
    model_key_edited(M0, tab, M).
char_inserted(Ch, M0, M) :-
    M0 = atto(P, Ls0, L-C, Top, _, St, Sz),
    nth0(L, Ls0, Line0, Rest),
    length(Before, C),
    append(Before, After, Line0),
    append(Before, [Ch | After], Line),
    nth0(L, Ls, Line, Rest),
    C1 is C + 1,
    M = atto(P, Ls, L-C1, Top, true, St, Sz).


'#editing'.

model_key_edited(M0, tab, M) :- !,
    foldl(char_inserted, [' ', ' ', ' ', ' '], M0, M).
model_key_edited(atto(P, Ls0, L-C, Top, _, St, Sz), return,
                 atto(P, Ls, L1-0, Top, true, St, Sz)) :- !,
    nth0(L, Ls0, Line, Rest0),
    length(Before, C),
    append(Before, After, Line),
    nth0(L, Rest1, Before, Rest0),
    L1 is L + 1,
    nth0(L1, Ls, After, Rest1).
model_key_edited(M0, backspace, M) :- !,
    M0 = atto(P, Ls0, L-C, Top, Mod, St, Sz),
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
    ;   M = atto(P, Ls0, L-C, Top, Mod, St, Sz)
    ).
model_key_edited(M0, delete, M) :- !,
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


'#view'.

:- det(view/2).
view((_-_)-M, View) :-
    model_view(M, View).

model_view(atto(_, _, _, _, _, _, unknown), []) :- !.
model_view(M, "Terminal too small") :-
    \+ model_fits(M), !.
model_view(M, column([Title, Text, Status, Menu])) :-
    M = atto(_, _, _, _, _, _, Cols-_),
    model_title(M, Title),
    model_text(M, Text),
    model_status_line(M, Status),
    Cols1 is Cols - 1,
    Menu = [clear(Cols1-0),
            row([style([negative], "^S"), " Save    ",
                 style([negative], "^R"), " Revert    ",
                 style([negative], "^Q"), " Quit"])].

model_title(atto(Path, _, _, _, Mod, _, Cols-_), style([negative], Line)) :-
    (   Mod == true
    ->  Flag = "Modified "
    ;   Flag = ""
    ),
    string_length(Flag, FlagLen),
    Avail is Cols - 8 - FlagLen,
    width_path_shown(Avail, Path, Shown),
    format(string(Line), " atto  ~w~t~w~*|", [Shown, Flag, Cols]).

% Path, shortened from the left to fit Avail characters.
width_path_shown(Avail, Path, Shown) :-
    atom_length(Path, Len),
    (   Len =< Avail
    ->  Shown = Path
    ;   Avail >= 2
    ->  Keep is Avail - 1,
        Skip is Len - Keep,
        sub_atom(Path, Skip, Keep, 0, Tail),
        atom_concat('…', Tail, Shown)
    ;   Shown = ''
    ).

model_text(M, editor_area(port(Cols-H, [clear(Cols1-H1), translate(0-NegTop, column(Numbered))]))) :-
    M = atto(_, Lines, _, Top, _, _, Cols-_),
    model_layout(M, G, W, H),
    Cols1 is Cols - 1,
    H1 is H - 1,
    NegTop is -Top,
    mapindexed(numbered_line(G, W), Lines, Numbered).

numbered_line(G, W, N, Chars, numbered_line(N, G, W, Chars)).

model_status_line(M, Line) :-
    M = atto(_, Lines, L-C, _, _, St, Cols-_),
    status_text(St, Msg),
    length(Lines, N),
    L1 is L + 1,
    C1 is C + 1,
    format(string(Line), " ~w~t~d/~d:~d ~*|", [Msg, L1, N, C1, Cols]).

status_text(none, "").
status_text(text(S), S).
status_text(confirm_quit, "Unsaved changes: ^Q again to quit, ^S to save").


'#components'.

% The text area. Claims the arrow keys, so they move the text cursor
% rather than the framework's cursor.
tui:alias_drawable(editor_area(D), D).

tui:at_event_is(editor_area(_), D, cursor(D)) :-
    direction(D).

% Line N: its number in a gutter G wide, then its text wrapped to W.
% Characters that would move the terminal's cursor are shown as spaces.
tui:alias_drawable(numbered_line(N, G, W, Chars), [style([faint], Gutter), G-0-wrapped(W, Shown)]) :-
    G1 is G - 1,
    format(string(Gutter), "~t~d~*| ", [N, G1]),
    maplist(char_shown, Chars, Shown).

char_shown(C, S) :-
    (   char_type(C, cntrl)
    ->  S = ' '
    ;   S = C
    ).
