:- module(hello, []).

/** <module> Hello

The smallest app: a view, an update, and a way out.

    swipl -p library=prolog examples/hello.pl
*/

:- use_module(library(tui)).

:- initialization(main, main).

main :-
    app((1-1)-[], view, update, _).

view(_, "Hello, TUI!" .\/ "Press q to quit").

update(q, S, result(S)).
update(_, S, S).
