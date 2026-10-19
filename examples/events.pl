:- module(events, []).

/** <module> Events — a custom component, and tagging instances

A custom component, counter/1, defined with the two hooks:
tui:alias_drawable/2 says what it draws, tui:at_event_is/3 what keys
mean on it. It sees where a key was pressed relative to itself, so
space on its [-] and on its [+] mean different things.

Two counters are tagged, apples : counter(A) and pears : counter(P), so
the counter's event counter-N reaches update as apples-N or pears-N.

Move the cursor with the arrows, and press space on a [-] or [+]. The
last line shows each event as it reaches update.

    swipl tui run events
*/

:- use_module(library(tui)).

:- multifile tui:alias_drawable/2.
:- multifile tui:at_event_is/3.

:- initialization(main, main).

main :-
    app((8-4)-counts(3, 5, none), view, update, _).


'#counter'.

% counter(N): [-] N [+], bold with the cursor on it.
tui:alias_drawable(counter(N), hover([bold], "[-] " .> N .> " [+]")).

% Space or return: on [-] (X 0..2) decrements, on [+] (from X = 5 + the
% width of N) increments. Anywhere else on the counter, nothing.
tui:at_event_is(counter(N), (X-_)-E, counter-N1) :-
    memberchk(E, [' ', return]),
    format(atom(A), "~w", [N]),
    atom_length(A, L),
    (   X =< 2
    ->  N1 is N - 1
    ;   X >= 5 + L
    ->  N1 is N + 1
    ).


'#app'.

view(_-counts(A, P, Last),
     column([style([bold], "Events"),
             style([faint], "Arrows move, space on [-] or [+] counts, q quits"),
             " ",
             "Apples " .> apples : counter(A),
             "Pears  " .> pears : counter(P),
             " ",
             style([faint], "Last event: ") .> literal(Last)])).

update(q, S, result(S)) :- !.
update(apples-A, C-counts(_, P, _), C-counts(A, P, apples-A)) :- !.
update(pears-P, C-counts(A, _, _), C-counts(A, P, pears-P)) :- !.
update(E, C-counts(A, P, _), C-counts(A, P, E)).
