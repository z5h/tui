:- module(atto, [atto/1]).

/** <module> atto — a tiny text editor

    swipl -p library=prolog examples/atto.pl -- FILE

The -- matters: without it, swipl takes a FILE ending in .pl as another
program to load (running its directives) instead of passing it to atto.

Edits FILE, which need not exist yet. Lines wrap to the screen width and
are numbered. ^S saves, ^R reverts to the file on disk, ^Q quits (twice
if there are unsaved changes). No undo.

This file shows how an editor is put together with tui. The editing
model (document, cursor, scrolling, files) is atto_lib.pl, driven by
commands; here are the key bindings that turn events into those
commands, and the view.

The text cursor is the framework's cursor. The view places it by drawing
the character under it as cursor(Char), and the editor area claims the
arrow keys, so they move the text cursor rather than the framework's.
*/

:- use_module(library(tui)).
:- use_module(library(tui/utils)).
:- use_module(atto_lib).

:- multifile tui:alias_drawable/2.
:- multifile tui:at_event_is/3.

:- initialization(main, main).

main :-
    current_prolog_flag(argv, Argv),
    (   Argv = [Path]
    ->  atto(Path)
    ;   format(user_error, "usage: swipl -p library=prolog examples/atto.pl -- FILE~n", []),
        halt(1)
    ).

atto(Path) :-
    path_model(Path, Model),
    app((1-1)-Model, state_view, event_update_with, _).


'#update'.

% Events become editing commands; the screen cursor is left unbound,
% because the view places it.
:- det(event_update_with/3).
event_update_with(E, _-M0, S) :-
    (   event_command(E, Command)
    ->  command_update_with(Command, M0, Next)
    ;   Next = M0
    ),
    (   Next = result(R)
    ->  S = result(R)
    ;   S = _-Next
    ).

% Key bindings. The text area is the screen less the title, status and
% menu rows.
event_command(terminal_size(Cols, Rows), resize(Cols, TextRows)) :- !,
    TextRows is Rows - 3.
event_command(ctrl+s, save) :- !.
event_command(ctrl+r, revert) :- !.
event_command(ctrl+q, quit) :- !.
event_command(move(D), move(D)) :- !.
event_command(E, move(E)) :-
    memberchk(E, [home, end, page_up, page_down]), !.
event_command(return, split_line) :- !.
event_command(backspace, delete_backward) :- !.
event_command(delete, delete_forward) :- !.
event_command(tab, indent) :- !.
event_command(paste(Text), insert_text(Text)) :- !.
event_command(Ch, insert(Ch)) :-
    atom(Ch),
    atom_length(Ch, 1),
    \+ char_type(Ch, cntrl).


'#view'.

:- det(state_view/2).
state_view(_-M, View) :-
    model_view(M, View).

model_view(M, []) :-
    model_size(M, unknown), !.
model_view(M, "Terminal too small") :-
    \+ model_fits(M), !.
model_view(M, column([Title, Text, Status, Menu])) :-
    model_size(M, Cols-_),
    model_title(M, Title),
    model_text(M, Text),
    model__status_line(M, Status),
    Cols1 is Cols - 1,
    Menu = [clear(Cols1-0),
            row([style([negative], "^S"), " Save    ",
                 style([negative], "^R"), " Revert    ",
                 style([negative], "^Q"), " Quit"])].

model_title(M, style([negative], Line)) :-
    model_path(M, Path),
    model_size(M, Cols-_),
    (   model_modified(M, true)
    ->  Flag = "Modified "
    ;   Flag = ""
    ),
    string_length(Flag, FlagLen),
    Avail is Cols - 8 - FlagLen,
    width_fit_with(Avail, Path, Shown),
    format(string(Line), " atto  ~w~t~w~*|", [Shown, Flag, Cols]).

% Path, shortened from the left to fit Avail characters.
width_fit_with(Avail, Path, Shown) :-
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

% The text area: the numbered, wrapped lines with a row in the visible
% Top..Top+H-1, offset so that row Top is at the top, and clipped. A line
% only partly visible at either edge is drawn whole; the port clips it.
model_text(M, editor_area(port(Cols-H, [clear(Cols1-H1), translate(0-Offset, column(Numbered))]))) :-
    model_lines(M, Lines),
    model_cursor(M, Cursor),
    model_top(M, Top),
    model_size(M, Cols-_),
    model_gutter_width_height(M, G, W, H),
    Cols1 is Cols - 1,
    H1 is H - 1,
    width_top_start_lines_skipped(W, Top, 1-0, Lines, N-Row, Visible),
    Offset is Row - Top,
    layout_index_row_lines_numbered(layout(G, W, Cursor, Top, H), N, Row, Visible, Numbered).

% Lines wrapped at W, without those entirely above screen row Top. The
% first remaining is line N, starting at screen row Row (from Start0 =
% N0-Row0 for the first line given).
width_top_start_lines_skipped(W, Top, N0-Row0, [Chars | Lines], Start, Visible) :-
    width_line_rows(W, Chars, Rows),
    Row0 + Rows =< Top, !,
    N1 is N0 + 1,
    Row1 is Row0 + Rows,
    width_top_start_lines_skipped(W, Top, N1-Row1, Lines, Start, Visible).
width_top_start_lines_skipped(_, _, Start, Lines, Start, Lines).

% Lines as numbered_lines, the first being line N and starting at screen
% row Row, up to the last with a row above Top + H. The cursor's line gets
% the cursor's column.
layout_index_row_lines_numbered(_, _, _, [], []) :- !.
layout_index_row_lines_numbered(layout(_, _, _, Top, H), _, Row, _, []) :-
    Row >= Top + H, !.
layout_index_row_lines_numbered(Layout, N, Row, [Chars | Lines], [D | Ds]) :-
    Layout = layout(G, W, L-C, _, _),
    width_line_rows(W, Chars, Rows),
    (   N =:= L + 1
    ->  Col = C
    ;   Col = none
    ),
    D = numbered_line(N, G, W, Chars, Col),
    N1 is N + 1,
    Row1 is Row + Rows,
    layout_index_row_lines_numbered(Layout, N1, Row1, Lines, Ds).

model__status_line(M, Line) :-
    model_lines(M, Lines),
    model_cursor(M, L-C),
    model_status(M, St),
    model_size(M, Cols-_),
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

tui:at_event_is(editor_area(_), _-D, move(D)) :-
    direction(D).

% Line N: its number in a gutter G wide, then its text wrapped to W.
% Characters that would move the terminal's cursor are shown as spaces.
% If the cursor is on the line, at column Col, the character there (or a
% space past the end) is drawn again as cursor(Char), placing the cursor.
tui:alias_drawable(numbered_line(N, G, W, Chars, Col),
                   [style([faint], Gutter), G-0-wrapped(W, Shown) | Cursor]) :-
    G1 is G - 1,
    format(string(Gutter), "~t~d~*| ", [N, G1]),
    maplist(char_shown, Chars, Shown),
    (   Col == none
    ->  Cursor = []
    ;   X is G + Col mod W,
        Y is Col // W,
        (   nth0(Col, Shown, Ch)
        ->  true
        ;   Ch = ' '
        ),
        Cursor = [X-Y-cursor(Ch)]
    ).

char_shown(C, S) :-
    (   char_type(C, cntrl)
    ->  S = ' '
    ;   S = C
    ).
