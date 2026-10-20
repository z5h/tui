:- module(reload, []).

/** <module> Reload — hot reloading, and what is written to stderr

Run it, then edit this file while it runs: change the greeting below,
or the frame's title, and press F5. The app reloads its modified source
with make/0 and paints the view as the new code draws it, keeping its
state (the count). Ctrl+L clears the screen and paints it again.

What is written to user_error while the app runs, make/0's messages
among it, reaches update as stderr(Text) instead of garbling the screen.
This app shows the last few lines. Try a syntax error, then F5: the
error appears here, and the rest of the file is still reloaded.

    swipl tui run reload
*/

:- use_module(library(tui)).
:- use_module(library(tui/components)).

:- initialization(main, main).

main :-
    app(_-model(0, []), view, update, _,
        [reload(f5), redraw(ctrl+l)]).

greeting("Edit me, then press F5.").

% model(Count, Lines): Count of space presses, Lines the last lines
% written to stderr, newest first.

update(q, S, result(S)) :- !.
update(' ', C-model(N0, L), C-model(N, L)) :- !,
    N is N0 + 1.
update(stderr(Text), C-model(N, L0), C-model(N, L)) :- !,
    split_string(Text, "\n", "", Parts),
    exclude(==(""), Parts, New),
    reverse(New, NewFirst),
    append(NewFirst, L0, L1),
    length(L1, Len),
    (   Len > 6
    ->  length(L, 6),
        append(L, _, L1)
    ;   L = L1
    ).
update(_, S, S).

view(_-model(N, Lines), View) :-
    greeting(Greeting),
    reverse(Lines, Oldest),
    maplist([L, style([faint], L)]>>true, Oldest, Shown),
    View = titled_frame(60-14, "Reload",
                        column([ Greeting,
                                 "",
                                 row(["Space pressed ", literal(N), " times."]),
                                 "",
                                 style([faint], "F5 reloads, Ctrl+L redraws, q quits."),
                                 "",
                                 "stderr:"
                               | Shown ])).
