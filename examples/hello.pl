:- module(hello, []).

/** <module> Hello — the smallest app

The smallest app: a view, an update, and a way out.

    swipl tui run hello
*/

:- use_module(library(tui)).

:- initialization(main, main).

main :-
    app((1-1)-[], view, update, _).

view(_, "Hello, TUI!" .\/ "Press q to quit").

update(q, S, result(S)).
update(_, S, S).
