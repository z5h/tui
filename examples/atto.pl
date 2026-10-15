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
    app((1-1)-Model, view, update, _).


'#update'.

% Events become editing commands; the screen cursor is left unbound,
% because the view places it.
:- det(update/3).
update(E, _-M0, S) :-
    (   event_command(E, Command)
    ->  model_command_next(Command, M0, Next)
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

:- det(view/2).
view(_-M, View) :-
    model_view(M, View).

model_view(M, []) :-
    model_size(M, unknown), !.
model_view(M, "Terminal too small") :-
    \+ model_fits(M), !.
model_view(M, column([Title, Text, Status, Menu])) :-
    model_size(M, Cols-_),
    model_title(M, Title),
    model_text(M, Text),
    model_status_line(M, Status),
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

% The text area: numbered, wrapped lines, scrolled to Top and clipped.
model_text(M, editor_area(port(Cols-H, [clear(Cols1-H1), translate(0-NegTop, column(Numbered))]))) :-
    model_lines(M, Lines),
    model_cursor(M, Cursor),
    model_top(M, Top),
    model_size(M, Cols-_),
    model_layout(M, G, W, H),
    Cols1 is Cols - 1,
    H1 is H - 1,
    NegTop is -Top,
    mapindexed(numbered_line(G, W, Cursor), Lines, Numbered).

% Line N, with the cursor's column if the cursor is on it.
numbered_line(G, W, L-C, N, Chars, numbered_line(N, G, W, Chars, Col)) :-
    (   N =:= L + 1
    ->  Col = C
    ;   Col = none
    ).

model_status_line(M, Line) :-
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

tui:at_event_is(editor_area(_), D, move(D)) :-
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
