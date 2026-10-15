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

% The frame's runs in standard order, with the cursor cell highlighted.
% The highlight is part of the cell's style, so the cursor cell forms its
% own run and moving the cursor changes the runs it touches.
limits_cursor_commands_runs(Limits, Cursor, Commands, Runs) :-
    include(limits_command_within(Limits), Commands, Onscreen),
    maplist(cursor_command_cell(Cursor), Onscreen, Cells0),
    keysort(Cells0, Cells),
    once(phrase(grouped_by_attributes(Runs0), Cells)),
    msort(Runs0, Runs).

limits_command_within(Limits, XY-_) :-
    limits_point_within(Limits, XY).

% Cells are keyed Y-X, so that sorting them by key is row-major.
cursor_command_cell(Cursor, (X-Y)-(_-A-C), (Y-X)-(Attrs-Char)) :-
    flatten(A, A1),
    raw_attributes_attributes(A1, A2),
    attributes_char_shown(A2, C, Attrs0, Char),
    (   Cursor = X-Y
    ->  append(Attrs0, [negative], Attrs)
    ;   Attrs = Attrs0
    ).

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

% The runs not already on screen. Runs within a frame never overlap, so
% a run in Previous is exactly what is at those cells.
runs_previous_changed(Runs, Previous, Changed) :-
    ord_subtract(Runs, Previous, Changed).
