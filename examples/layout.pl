:- module(layout, []).

/** <module> Layout

The core drawables, each labelled. There is no cursor (the state's is
left unbound), so every key goes to update.

    swipl -p library=prolog examples/layout.pl
*/

:- use_module(library(tui)).

:- multifile tui:alias_drawable/2.

:- initialization(main, main).

main :-
    app(_-[], view, update, _).

update(q, S, result(S)).
update(_, S, S).

view(_, column([style([bold], "Layout"),
                style([faint], "q quits"),
                " ",
                row([Left, "    ", Right])])) :-
    string_chars("The quick brown fox jumps over the lazy dog.", Fox),
    Left = column([
        sample(".>", "left" .> " then " .> "right"),
        sample(".<", "right" .< " then " .< "left"),
        sample(".\\/", "top" .\/ "bottom"),
        sample("./\\", "bottom" ./\ "top"),
        sample("row/1", row(["one", " ", "two", " ", "three"])),
        sample("column/1", column(["one", "two", "three"])),
        sample("wrapped/2", wrapped(16, Fox))
    ]),
    Right = column([
        sample("box/2", row([box(6-3, thin), " ", box(6-3, thick), " ", box(6-3, double),
                             " ", box(6-3, box_chars('-', '|', '+', '+', '+', '+'))])),
        sample("X-Y-D", [box(8-3, thin), 2-1-"hi"]),
        sample("lists", ["overdrawn", "OVER"]),
        sample("port/2", port(7-1, "clipped to seven")),
        sample("line/3", line('·', 0-0, 11-0)),
        sample("style/2", row([style([bold], "bold"), " ",
                               style([faint], "faint"), " ",
                               style([italic], "italic"), " ",
                               style([underline], "underline")])),
        sample("", row([style([negative], "negative"), " ",
                        style([fg(red)], "red"), " ",
                        style([fg(black), bg(yellow)], "on yellow")]))
    ]).

% sample(Name, D): Name, faint in a column of its own, beside D, and a
% blank line below.
tui:alias_drawable(sample(Name, D), (port(11-1, style([faint], Name)) .> D) .\/ " ").
