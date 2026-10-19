:- module(gallery, [state0/1, view/2]).

/** <module> Gallery — the ready-made components, with the mouse

The ready-made components of library(tui/components), each tagged with
its key in the model, so their events arrive at update as Key-Value.

Arrows move the cursor; the component under it shows bold. Space or
return toggles a check box or presses a button. Type into the input.
Shift+arrows drag the scroll's content, or on a scrollbar its thumb;
page up and down page it. OK prints the model, Cancel and q quit.

The mouse is on (app/5 option mouse(true)): a click moves the cursor
and presses or toggles what it is on, the wheel scrolls, and pressing or
dragging on a scrollbar moves its thumb. Hold shift (option on macOS)
to select text with the mouse instead.

    swipl tui run gallery
*/

:- use_module(library(tui)).
:- use_module(library(tui/components)).
:- use_module(library(tui/assocs)).

:- multifile tui:alias_drawable/2.

:- initialization(main, main).

main :-
    state0(S),
    app(S, view, update, Result, [mouse(true)]),
    format("~p~n", [Result]).

state0((2-3)-[ wrap-true,
               numbers-false,
               name-_,
               list-(0-0),
               last-none ]).

view(_-M, titled_frame(56-17, "Gallery", column([row([Left, "   ", Right]),
                                                 " ",
                                                 Last]))) :-
    assocs_pairs(M, [wrap-Wrap, numbers-Numbers, name-Name, list-Offset, last-E]),
    lines(Lines),
    Left = column([ label("check_box/2"),
                    wrap : check_box("Wrap lines", Wrap),
                    numbers : check_box("Line numbers", Numbers),
                    " ",
                    label("input/3"),
                    name : input(16, "your name", Name),
                    " ",
                    label("button/1"),
                    row([ok : button("OK"), " ", cancel : button("Cancel")]),
                    " ",
                    style([faint], "q quits")
                  ]),
    Right = column([ label("scroll/3"),
                     list : scroll(30-12, Offset, column(Lines))
                   ]),
    Last = label("Last event: ") .> literal(E).

tui:alias_drawable(label(Text), style([faint], Text)).

% Numbered lines, some too long for the scroll's width.
lines(Lines) :-
    Words = [lorem, ipsum, dolor, sit, amet, consectetur, adipiscing, elit],
    findall(Line,
            ( between(1, 40, I),
              N is 1 + I mod 7,
              findall(W, ( between(1, N, J), K is (I + J) mod 8, nth0(K, Words, W) ), Ws),
              atomic_list_concat([I | Ws], ' ', Line) ),
            Lines).

update(q, S, result(S)) :- !.
update(ok-pressed, _-M, result(M)) :- !.
update(cancel-pressed, _, result(cancelled)) :- !.
update(K-V, C-M0, C-M) :-
    assocs_pair(M0, K-_), !,
    pair_pair_assocs_assocs(K-_, K-V, M0, M1),
    pair_pair_assocs_assocs(last-_, last-(K-V), M1, M).
update(E, C-M0, C-M) :-
    pair_pair_assocs_assocs(last-_, last-E, M0, M).
