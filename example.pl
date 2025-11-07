:- module(example, [go/0
                   ]).

:- reexport(tui).
:- use_module(components).
:- use_module(local(core/core)).
:- use_module(local(core/assocs)).


tui:tui_module(example).

:- public(alias_drawable/2).
:- discontiguous(alias_drawable/2).

:- public(at_event_is/3).
:- discontiguous(at_event_is/3).


:- op(602, yfx, ~>).
:- op(602, fy, ~>).
:- op(601, xfy, '.>').
:- op(601, xfy, '.\\/').
:- op(601, xfy, '<-..').


init_checks(Checks) :-
    findall(true, between(1, 100, N), Checks).

init(M) :-
    init_checks(Cs),
    M =
        5-5-[ checks-Cs,
              scroll(1)-(0-0),
              scroll(2)-(0-0),
              scroll(3)-(0-0),
              moveable(1)-(0-0-false),
              moveable(2)-(0-0-false),
              moveable(3)-(0-0-false)
            ].

:- det(update/3).
update(C, S0, (X-Y)-M1) :-
    (X-Y)-M0 = S0,
    (  C = Key-Change
    -> pair_pair_assocs_assocs(Key-_, Key-Change, M0, M1)
    ;  atom(C)
    -> M1 = M0
    ), !.

update(C, S0, (X-Y)-M1) :-
    writeln(bad_update),
    writeln(C),
    writeln(S0),
    fail.

:- table(int_text(I, T)).
int_text(I, T) :-
    M is (I - 1) mod 9,
    nth0(M, [lorem, ipsum, dolor, sit, amet, consectetur, adipiscing, elit, 'sed do eiusmod tempor'], W),
    atomic_list_concat([I, ' ', W], T), !.

alldif(_, []).
alldif(A, [H|T]) :-
    dif(A, H),
    alldif(A, T),
    alldif([H|T]).

alldif([H|T]) :- alldif(H, T).

:- det(view/2).
view((_X-_Y)-M0, View) :-
    alldif([A, B, C]),
    assocs_pairs(M0,
                 [
                     moveable(A)-MVA,
                     moveable(B)-MVB,
                     moveable(C)-MVC,
                     scroll(A)-SOA,
                     scroll(B)-SOB,
                     scroll(C)-SOC,
                     checks-Checks
                 ]), !,

    moveable_color(A, CA),
    moveable_color(B, CB),
    moveable_color(C, CC),
    View =
        titled_frame(80-30, "My App",
                     [ id(C, moveable, MVC,
                          1-1-style([fg(CC)],
                                    id(C, scroll, 20-15, SOC,
                                       checks(Checks)
                                    ))
                       ),
                       id(B, moveable, MVB,
                          1-1-style([fg(CB)],
                                    id(B, scroll, 20-15, SOB,
                                       checks(Checks)
                                    ))
                       ),

                       id(A, moveable, MVA,
                          1-1-style([fg(CA)],
                                    id(A, scroll, 20-15, SOA,
                                       checks(Checks)
                                    ))
                       )
                     ]
        ).

moveable_color(1, red).
moveable_color(2, green).
moveable_color(3, blue).


alias_drawable(IDed, Drawable) :-
    IDed =.. [id, _Id, Alias  |Parameters],
    Drawable =.. [Alias  |Parameters].

at_event_is(IDedAlias, Alias-Updated, IDed-Updated) :-
    IDedAlias =.. [id, Id, Alias  |_],
    IDed =.. [Alias, Id].


to_ided_checkbox(I, T, id(I, check_box, L, T)) :- int_text(I, L).

alias_drawable(checks(Checks), View) :-
    mapindexed(to_ided_checkbox, Checks, IndexedChecks),
    View = column(IndexedChecks).

alias_drawable(indexed_check(I, Bool), View) :-
    View = check_box(I, Bool).

list_index_is_updated([_|T], 1, H, [H|T]) :- !.
list_index_is_updated([H|T], N, Is, [H|U]) :-
    N > 1,
    Next is N - 1,
    list_index_is_updated(T, Next, Is, U).

at_event_is(checks(Checks), check_box(I)-T, checks-Updated) :-
    list_index_is_updated(Checks, I, T, Updated).

% moveable
alias_drawable(moveable(DX-DY-Moving, Drawable), View) :-
    (  Moving
    -> View = [
                  1-1-style([fg(black), bg(black)], translate(DX-DY, Drawable)),
                  0-0-style([faint], translate(DX-DY, Drawable))
              ]
    ;  View = translate(DX-DY, Drawable)
    ).

not(true, false).
not(false, true).

at_event_is(moveable(DX-DY-Moving, _), ' ', moveable-(DX-DY-MovingToggle)) :-
    not(Moving, MovingToggle), !.

at_event_is(moveable(DX-DY-true, _), moved(D, _, _), moveable-(DX1-DY1-true)) :-
    ( D = left, DX1 is DX - 1, DY1 is DY
    ; D = right, DX1 is DX + 1, DY1 is DY
    ; D = up, DX1 is DX, DY1 is DY - 1
    ; D = down, DX1 is DX, DY1 is DY + 1
    ), !.

go :-
    reset,
    tui_init,
    init(M),
    with_tty_raw(
        app(M, view, update, Result)),
    show_cursor,
    clear_screen,
    writeln(Result).
