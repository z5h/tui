:- module(tui_render,
          [
            limits_cursor_commands_runs/4,
            runs_previous_changed/3
          ]).

/** <module> Rendering

Turns a frame's commands into runs: maximal stretches of adjacent cells
on one row with the same attributes, (X-Y)-(Attrs-Chars). Painting a
frame needs only the runs not already on screen.
*/

:- use_module(library(tui/utils)).
:- use_module(library(tui/drawable)).
:- use_module(library(tui/hover)).


'#runs'.

%!  limits_cursor_commands_runs(+Limits, +Cursor, +Commands, -Runs) is det.
%
%  Runs are the frame's runs, (X-Y)-(Attrs-Chars), within Limits and in
%  standard order. The cells drawn by highlight/1, and the cell at Cursor
%  (X-Y, or none) unless drawn under cursor_hidden, are highlighted, once
%  however many apply (see highlight/1). The highlight is part of the cell's style, so the cursor
%  cell forms its own run and moving the cursor changes the runs it
%  touches. A cursor on a cell nothing was drawn on shows as a negative
%  space.
limits_cursor_commands_runs(Limits, Cursor, Commands, Runs) :-
    include(limits_command_within(Limits), Commands, Onscreen),
    maplist(cursor_command_cell(Cursor), Onscreen, Cells0),
    limits_cursor_cells_shown(Limits, Cursor, Cells0, Cells1),
    keysort(Cells1, Cells),
    once(phrase(grouped_by_attributes(Runs0), Cells)),
    msort(Runs0, Runs).

limits_command_within(Limits, XY-_) :-
    limits_point_within(Limits, XY).

% Cells are keyed Y-X, so that sorting them by key is row-major. A
% holds one list per style, innermost first; flattened outermost first,
% the innermost style is applied last and wins. Under cursor_hidden the
% cursor's cell is not highlighted for the cursor.
cursor_command_cell(Cursor, (X-Y)-(Stack-A-C), (Y-X)-(Attrs-Char)) :-
    reverse(A, A0),
    flatten(A0, A1),
    raw_attributes_attributes(A1, A2),
    partition(==(cursor_hidden), A2, Hidden, A3),
    attributes_char_shown(A3, C, Attrs0, Char),
    (   (   Cursor = X-Y,
            Hidden == []
        ;   memberchk(_-highlight(_), Stack)
        )
    ->  char_attributes_highlighted(Char, Attrs0, Attrs)
    ;   Attrs = Attrs0
    ).

% The highlight: negative added, or else removed; a space that would
% then be blank (no underline, the default background) loses negative
% and is underlined instead.
char_attributes_highlighted(Char, Attrs0, Attrs) :-
    (   memberchk(negative, Attrs0)
    ->  exclude(==(negative), Attrs0, Attrs1),
        (   Char == ' ',
            \+ memberchk(underline, Attrs0),
            attributes_background_default(Attrs0)
        ->  append(Attrs1, [underline], Attrs)
        ;   Attrs = Attrs1
        )
    ;   append(Attrs0, [negative], Attrs)
    ).

% The last background set, if any, is the default.
attributes_background_default(Attrs) :-
    include(is_background_attribute, Attrs, Bgs),
    (   last(Bgs, Bg)
    ->  Bg == bg(default)
    ;   true
    ).

is_background_attribute(bg(_)).
is_background_attribute(bg(_, _, _)).
is_background_attribute(hbg(_)).

limits_cursor_cells_shown(Limits, X-Y, Cells, [(Y-X)-([negative]-' ') | Cells]) :-
    limits_point_within(Limits, X-Y),
    \+ memberchk((Y-X)-_, Cells), !.
limits_cursor_cells_shown(_, _, Cells, Cells).

% Runs of cells on the same row, at consecutive X, with equal attributes.
% Cells are keyed Y-X and sorted; runs are keyed X-Y.
grouped_by_attributes([(X-Y)-(Attrs-[C | Cs]) | Runs]) -->
    [(Y-X)-(Attrs-C)],
    run_chars(X, Y, Attrs, Cs),
    grouped_by_attributes(Runs).
grouped_by_attributes([]) --> [].

run_chars(X0, Y, Attrs, [C | Cs]) -->
    { X is X0 + 1 },
    [(Y-X)-(Attrs-C)], !,
    run_chars(X, Y, Attrs, Cs).
run_chars(_, _, _, []) --> [].


'#changes'.

%!  runs_previous_changed(+Runs, +Previous, -Changed) is det.
%
%  Changed are the runs to paint to go from Previous to Runs: those not
%  already on screen, and blank runs for the cells drawn before but no
%  longer. Runs within a frame never overlap, so a run in Previous is
%  exactly what is at those cells, and a removed run can only be covered
%  by a new one.
runs_previous_changed(Runs, Previous, Changed) :-
    ord_subtract(Runs, Previous, New),
    ord_subtract(Previous, Runs, Removed),
    (   Removed == []
    ->  Changed = New
    ;   runs_cells(Removed, Gone0),
        runs_cells(New, Drawn),
        ord_subtract(Gone0, Drawn, Gone),
        findall((Y-X)-([]-' '), member(Y-X, Gone), BlankCells),
        once(phrase(grouped_by_attributes(Blanks0), BlankCells)),
        msort(Blanks0, Blanks),
        ord_union(New, Blanks, Changed)
    ).

% The cells Runs cover, as a sorted list of Y-X.
runs_cells(Runs, Cells) :-
    findall(Y-X,
            ( member((X0-Y)-(_-Chars), Runs),
              length(Chars, N),
              X1 is X0 + N - 1,
              between(X0, X1, X) ),
            Cells0),
    sort(Cells0, Cells).
