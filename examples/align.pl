:- module(align, []).

/** <module> Align — zones, aligns and tables

Zones, aligns and tables.

zone(W-H, D) has extent W×H whatever D draws; an align directly in it
(or in its list) is placed against its edges. The view is drawn in a
zone the size of the terminal, so its top-level aligns place the title,
the samples and the footer. Each table cell is a zone too. Tab cycles
the table's style; q quits.

    swipl tui run align
*/

:- use_module(library(tui)).

:- initialization(main, main).

main :-
    app(_-thin, view, update, _).

styles([thin, thick, double, space, empty]).

update(q, S, result(S)) :- !.
update(tab, C-Style0, C-Style) :- !,
    styles(Styles),
    (   nextto(Style0, Style, Styles)
    ->  true
    ;   Styles = [Style | _]
    ).
update(_, S, S).

view(_-Style,
     [ align(up_left, column([style([bold], "Align"),
                              style([faint], "Tab cycles the table style, q quits")])),
       align(center, row([Directions, "    ", Table])),
       align(down_right, style([faint], "examples/align.pl")) ]) :-
    findall(align(D, style([bold], D)),
            member(D, [up_left, up, up_right, left, center, right,
                       down_left, down, down_right]),
            Aligned),
    Directions = column([style([faint], "zone(30-7, [align(Dir, Dir), ...])"),
                         [box(32-9, thin), 1-1-zone(30-7, Aligned)]]),
    Table = column([style([faint], "table(" .> Style .> ", Rows)"),
                    table(Style, Rows)]),
    Rows = [ [ align(center, style([bold], "Fruit")),
               align(center, style([bold], "Qty")),
               align(center, style([bold], "Note")) ],
             [ "apples", align(right, 12), "crisp" ],
             [ "kiwi", align(right, 3), "fuzzy" .\/ "and green" ],
             [ "plums", align(right, 140) ] ].
