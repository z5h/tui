:- module(hello, []).

/** <module> Hello — the smallest app

The smallest app: a view, an update, and a result. Press a button (click
it, or move to it and press space or return); the app ends with the
button's name, which main prints.

    swipl tui run hello
*/

:- use_module(library(tui)).
:- use_module(library(tui/components)).

:- initialization(main, main).

main :-
    app((1-3)-none, view, update, Pressed, [mouse(true)]),
    format("You pressed ~w.~n", [Pressed]).

view(_, column(["Hello, TUI!",
                "",
                row([yes : button("Yes"), " ", no : button("No")])])).

update(yes-pressed, _, result('Yes')).
update(no-pressed, _, result('No')).
update(_, S, S).
