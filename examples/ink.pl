:- module(ink, [ink/1]).

/** <module> ink — an editor for text styled with ANSI escapes

    swipl tui run ink FILE

Edits FILE, which need not exist yet, as a screen 80 columns wide, its
rows numbered if the terminal has room beside them: the
file is replayed as a terminal would (cursor movement and SGR styles;
anything else is ignored), and saved as plain rows of styled text, so
that `cat FILE` shows it. See sgr_screen_lib.pl for both.

Typing overwrites, keeping the style of the cell typed on. Return moves
to the start of the next row; Shift+Return (or ^O, for terminals that
cannot tell Shift+Return from Return) adds an empty row after the
cursor's, Shift+Delete deletes the cursor's row. Backspace and Delete
erase characters, not styles.

Shift+arrows (Shift+Home, Shift+End, ...) or a mouse drag select a
rectangle; Escape clears it. Styles apply to the selected cells, or
without a selection to the cursor's: ^B bold, ^D dim, ^T italic, ^U
underline, ^N inverse, ^K crossed out (each toggled: removed if every
cell has it, else added), ^F and ^G then a digit for the foreground and
background colour (1-8 black, red, green, yellow, blue, magenta, cyan,
white; 0 the default, which is no colour), ^E plain.

^C copies the selected cells, styles and all, ^X cuts them (leaving
empty cells), ^V pastes them with their top-left corner at the cursor,
overwriting. The clipboard is ink's own: a paste from the terminal (with
its own paste key) arrives as text, typed in at the cursor. In a
terminal without the Kitty keyboard protocol, ^C may interrupt Prolog
rather than reach ink.

^S saves, ^R reverts to the file on disk, ^Q quits; with unsaved changes
^R and ^Q ask first, and are pressed again to confirm. No undo.

As in atto.pl, the editing model is a library (ink_lib.pl) driven by
commands; here are the key bindings and the view. The cursor is the
framework's: the view draws the cell under it as cursor(Cell), and the
canvas area claims the arrow keys. Selected cells are drawn as
highlight(...), the same highlight as the cursor's; the cursor's cell is
always one of them, and highlighted once.
*/

:- use_module(library(tui)).
:- use_module(library(tui/utils)).
:- use_module(ink_lib).
:- use_module(sgr_screen_lib).

:- multifile tui:alias_drawable/2.
:- multifile tui:at_event_is/3.

:- initialization(main, main).

main :-
    current_prolog_flag(argv, Argv),
    (   Argv = [Path]
    ->  ink(Path)
    ;   format(user_error, "usage: swipl tui run ink FILE~n", []),
        halt(1)
    ).

ink(Path) :-
    path_model(Path, Model),
    app((1-1)-Model, state_view, event_update_with, _, [mouse(true)]).


'#update'.

% Events become editing commands; the screen cursor is left unbound,
% because the view places it.
:- det(event_update_with/3).
event_update_with(E, _-M0, S) :-
    (   event_model_command(E, M0, Command)
    ->  command_update_with(Command, M0, Next)
    ;   Next = M0
    ),
    (   Next = result(R)
    ->  S = result(R)
    ;   S = _-Next
    ).

% Key bindings. The canvas area is the screen less the title, status and
% two menu rows. While a colour is asked for, a digit answers.
event_model_command(Ch, M, style(set(Attr))) :-
    model_status(M, ask(Kind)),
    digit_colour(Ch, C), !,
    Attr =.. [Kind, C].
event_model_command(E, _, Command) :-
    event_command(E, Command).

% The colour keys, in keyboard order: 1-8 the palette, 0 the default.
digit_colour('1', black).
digit_colour('2', red).
digit_colour('3', green).
digit_colour('4', yellow).
digit_colour('5', blue).
digit_colour('6', magenta).
digit_colour('7', cyan).
digit_colour('8', white).
digit_colour('0', default).

event_command(terminal_size(Cols, Rows), resize(Cols, CanvasRows)) :- !,
    CanvasRows is Rows - 4.
event_command(ctrl+s, save) :- !.
event_command(ctrl+r, revert) :- !.
event_command(ctrl+q, quit) :- !.
event_command(ctrl+c, copy) :- !.
event_command(ctrl+x, cut) :- !.
event_command(ctrl+v, paste) :- !.
event_command(escape, escape) :- !.
event_command(ctrl+K, style(toggle(Attr))) :-
    key_attribute(K, Attr), !.
event_command(ctrl+e, style(plain)) :- !.
event_command(ctrl+f, ask(fg)) :- !.
event_command(ctrl+g, ask(bg)) :- !.
event_command(move(D), move(D)) :- !.
event_command(extend(D), extend(D)) :- !.
event_command(point(XY), point(XY)) :- !.
event_command(extend_to(XY), extend_to(XY)) :- !.
event_command(_-mouse(scroll, D), scroll(D)) :-
    memberchk(D, [up, down]), !.
event_command(E, move(E)) :-
    memberchk(E, [home, end, page_up, page_down, tab]), !.
event_command(shift+E, extend(E)) :-
    memberchk(E, [home, end, page_up, page_down]), !.
event_command(return, return) :- !.
event_command(shift+return, new_line) :- !.
event_command(ctrl+o, new_line) :- !.
event_command(shift+delete, delete_line) :- !.
event_command(backspace, erase_backward) :- !.
event_command(delete, erase) :- !.
event_command(paste(Text), type_text(Text)) :- !.
event_command(Ch, type(Ch)) :-
    atom(Ch),
    atom_length(Ch, 1),
    \+ char_type(Ch, cntrl).

key_attribute(b, bold).
key_attribute(d, faint).
key_attribute(t, italic).
key_attribute(u, underline).
key_attribute(n, negative).
key_attribute(k, crossed_out).


'#view'.

:- det(state_view/2).
state_view(_-M, View) :-
    model_view(M, View).

model_view(M, []) :-
    model_size(M, unknown), !.
model_view(M, "Terminal too small: ink needs 80 columns") :-
    \+ model_fits(M), !.
model_view(M, column([Title, Canvas, Status, Menu])) :-
    model_title(M, Title),
    model_canvas(M, Canvas),
    model__status_line(M, Status),
    model_menu(Menu).

model_title(M, style([negative], Line)) :-
    model_path(M, Path),
    model_size(M, Cols-_),
    (   model_modified(M, true)
    ->  Flag = "Modified "
    ;   Flag = ""
    ),
    string_length(Flag, FlagLen),
    Avail is Cols - 7 - FlagLen,
    width_fit_with(Avail, Path, Shown),
    format(string(Line), " ink  ~w~t~w~*|", [Shown, Flag, Cols]).

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

% The canvas area: the visible rows, numbered in a gutter G wide (none if
% G is 0), the selection drawn again over them, highlighted, a faint edge
% after the last column if there is room, and the cursor. Below the last
% row nothing is drawn, so the numbers show where the rows end. The
% cursor's cell is always selected, and highlighted once either way.
model_canvas(M, canvas_area(port(Cols-H, [clear(Cols-H), Edge, column(Ds), Selection, CX-CY-cursor(Cell)]))) :-
    model_size(M, Cols-H),
    model_rows(M, Rows),
    model_top(M, Top),
    model_gutter(M, G),
    model_selection(M, Rect),
    model_cursor(M, X-Y),
    length(Skipped, Top),
    append(Skipped, Rest, Rows),
    (   length(Visible, H),
        append(Visible, _, Rest)
    ->  true
    ;   Visible = Rest
    ),
    foldl(gutter_row_drawable(G), Visible, Ds, Top, _),
    rows_top_height_gutter_rect_selection(Rows, Top, H, G, Rect, Selection),
    screen_width(W),
    EdgeX is G + W,
    (   Cols > EdgeX
    ->  length(Bars, H),
        maplist(=("│"), Bars),
        Edge = EdgeX-0-style([faint], column(Bars))
    ;   Edge = []
    ),
    nth0(Y, Rows, Row),
    nth0(X, Row, A-Ch),
    Cell = style(A, Ch),
    CX is G + X,
    CY is Y - Top.

% Row Y: its number, faint and right-aligned in the gutter, then its
% cells grouped into runs of the same style.
gutter_row_drawable(G, Row, [Number, G-0-row(Runs)], Y, Y1) :-
    Y1 is Y + 1,
    (   G > 0
    ->  G1 is G - 1,
        format(string(S), "~t~d~*| ", [Y1, G1]),
        Number = style([faint], S)
    ;   Number = []
    ),
    cells_runs(Row, Runs).

% The selected cells of the visible rows, highlighted, at their places
% in the canvas area.
rows_top_height_gutter_rect_selection(Rows, Top, H, G, rect(X0-Y0, X1-Y1), highlight(Ds)) :-
    Last is min(Y1, Top + H - 1),
    First is max(Y0, Top),
    (   First =< Last
    ->  numlist(First, Last, Ys)
    ;   Ys = []
    ),
    DX is G + X0,
    findall(DX-DY-row(Runs),
            ( member(Y, Ys),
              nth0(Y, Rows, Row),
              DY is Y - Top,
              Len is X1 - X0 + 1,
              length(Before, X0),
              length(Cells, Len),
              append(Before, Rest, Row),
              append(Cells, _, Rest),
              cells_runs(Cells, Runs)
            ),
            Ds).

cells_runs([], []).
cells_runs([A-Ch | Cells0], [style(A, chars([Ch | Chs])) | Runs]) :-
    same_style_chars(Cells0, A, Chs, Cells),
    cells_runs(Cells, Runs).

same_style_chars([A-Ch | Cells0], A, [Ch | Chs], Cells) :- !,
    same_style_chars(Cells0, A, Chs, Cells).
same_style_chars(Cells, _, [], Cells).

% The status: a message (or, when a colour is asked for, the colours),
% and on the right the cursor's style and position.
model__status_line(M, zone(Cols-1, [Left, align(right, Right)])) :-
    model_size(M, Cols-_),
    model_status(M, St),
    status_drawable(St, Left),
    model_rows(M, Rows),
    model_cursor(M, X-Y),
    nth0(Y, Rows, Row),
    nth0(X, Row, A-_),
    length(Rows, N),
    X1 is X + 1,
    Y1 is Y + 1,
    maplist(term_to_atom, A, Names),
    atomic_list_concat(Names, ' ', Style),
    format(string(Right), "~w  ~d/~d:~d ", [Style, Y1, N, X1]).

status_drawable(none, "").
status_drawable(text(S), [" ", S]).
status_drawable(confirm(quit), " Unsaved changes: ^Q again to quit, ^S to save").
status_drawable(confirm(revert), " Unsaved changes: ^R again to revert to the file on disk").
% Each colour is its digit, unstyled, then a patch of that palette entry
% (fg and bg share the palette). Default is no colour at all; its patch
% is the terminal's own: a negative space shows the default foreground,
% a plain space the default background.
status_drawable(ask(Kind), row([" ", Label | Swatches])) :-
    kind_label(Kind, Label),
    findall([Key, style([bg(C)], "  "), " "],
            ( digit_colour(Key, C),
              C \== default ),
            Swatches0),
    append(Swatches0, Swatches1),
    digit_colour(DefaultKey, default),
    kind_default_patch(Kind, Patch),
    append(Swatches1, [" ", DefaultKey, Patch, " default"], Swatches).

kind_default_patch(fg, style([negative], "  ")).
kind_default_patch(bg, "  ").

kind_label(fg, "Foreground: ").
kind_label(bg, "Background: ").

model_menu(column([row(Keys1), row(Keys2)])) :-
    keys_drawables(["^S"-"save", "^R"-"revert", "^Q"-"quit", "^C"-"copy", "^X"-"cut",
                    "^V"-"paste", "^O"-"new line", "S-Del"-"del line"], Keys1),
    keys_drawables(["^B"-"bold", "^D"-"dim", "^T"-"italic", "^U"-"underline",
                    "^N"-"inverse", "^K"-"strike", "^F"-"fg", "^G"-"bg", "^E"-"plain"], Keys2).

keys_drawables(Pairs, Ds) :-
    foldl(key_drawables, Pairs, Ds, []).

key_drawables(Key-Label, [style([negative], Key), " ", Label, " " | Ds], Ds).


'#components'.

% The canvas area. Claims the arrow keys, plain and with shift, so they
% move the text cursor rather than the framework's, and the left button:
% a press points at a cell, a drag selects.
tui:alias_drawable(canvas_area(D), D).

tui:at_event_is(canvas_area(_), _-D, move(D)) :-
    direction(D).
tui:at_event_is(canvas_area(_), _-(shift+D), extend(D)) :-
    direction(D).
tui:at_event_is(canvas_area(_), XY-mouse(press, left), point(XY)).
tui:at_event_is(canvas_area(_), XY-mouse(drag, left), extend_to(XY)).
