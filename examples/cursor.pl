:- module(cursor, []).

/** <module> Cursor

Two ways to have a cursor.

Free: the state holds the cursor, and the arrow keys move it by default,
anywhere within what the view drew.

Menu: the view places the cursor itself, by drawing cursor(Item) on the
selected item; this overrides the state's cursor. The menu claims up and
down to change the selection. Left and right still move the state's
cursor, but the view puts it back: it does not move.

Tab switches between the two; q quits.

    swipl -p library=prolog examples/cursor.pl
*/

:- use_module(library(tui)).

:- multifile tui:alias_drawable/2.
:- multifile tui:at_event_is/3.

:- initialization(main, main).

main :-
    app((1-5)-model(free, 0), view, update, _).


'#menu'.

items(["Apples", "Pears", "Plums", "Cherries"]).

% menu(Items, Sel, Active): Items, one per row, Sel marked. When Active,
% the cursor is on Sel, and up and down move it.
tui:alias_drawable(menu(Items, Sel, Active), column(Rows)) :-
    findall(Row,
            ( nth0(I, Items, Item),
              item_row(I, Sel, Active, Item, Row) ),
            Rows).

item_row(Sel, Sel, true, Item, style([bold], "> " .> cursor(Item))) :- !.
item_row(Sel, Sel, false, Item, style([bold], "> " .> Item)) :- !.
item_row(_, _, _, Item, "  " .> Item).

tui:at_event_is(menu(_, Sel, true), _-up, menu-Sel1) :-
    Sel > 0,
    Sel1 is Sel - 1.
tui:at_event_is(menu(Items, Sel, true), _-down, menu-Sel1) :-
    length(Items, N),
    Sel < N - 1,
    Sel1 is Sel + 1.


'#app'.

view(_-model(Mode, Sel),
     column([style([bold], "Cursor"),
             style([faint], "Tab switches mode, q quits"),
             " ",
             "Mode: " .> style([bold], Mode) .> style([faint], Help),
             Field,
             " ",
             menu(Items, Sel, Active)])) :-
    items(Items),
    mode_active_help(Mode, Active, Help),
    Field = column(["....................",
                    "....................",
                    "...................."]).

mode_active_help(free, false, " (arrows move the cursor anywhere drawn)").
mode_active_help(menu, true, " (the view places the cursor on the selection)").

update(q, S, result(S)) :- !.
update(tab, C-model(free, Sel), C-model(menu, Sel)) :- !.
update(tab, C-model(menu, Sel), C-model(free, Sel)) :- !.
update(menu-Sel, C-model(Mode, _), C-model(Mode, Sel)) :- !.
update(_, S, S).
