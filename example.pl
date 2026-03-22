:- module(example, [go/0
                   ]).

:- use_module(tui).
:- use_module(utils).
:- use_module(assocs).
:- use_module(components).

:- op(601, xfy, '.>').
:- op(601, xfy, '.<').
:- op(601, xfy, '.\\/').
:- op(601, xfy, './\\').


init_checks(Checks) :-
    findall(true, between(1, 100, _), Checks).

init(M) :-
    init_checks(Cs),
    M =
        5-5-[ checks-Cs,
              scroll(1)-(0-0),
              scroll(2)-(0-0),
              scroll(3)-(0-0),
              moveable(1)-(0-0-false),
              moveable(2)-(20-0-false),
              moveable(3)-(40-0-false),
              time-' ',
              last_event-'n/a'
            ].

:- det(update/3).
:- public(update/3).
update(C, S0, (X-Y)-M1) :-
    (X-Y)-M0 = S0,
    (  C = Key-Change
    -> pair_pair_assocs_assocs(Key-_, Key-Change, M0, M1)

    ;  pair_pair_assocs_assocs(last_event-_, last_event-C, M0, M1)
    ), !.

update(q, S0, result(S0)) :- !.

:- table(int_text/2).
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
:- public(view/2).
view((X-Y)-M, View) :-

    % we want the most recently updated movable to be rendered last (over the others)
    % so this is just to establist A,B,C as the IDs in the order we want.
    alldif([A, B, C]),
    assocs_pairs(M,
                 [ moveable(A)-_,
                   moveable(B)-_,
                   moveable(C)-_,
                   time-T,
                   last_event-LastEvent
                 ]), !,

    View =
        titled_frame(80-25, "My App",
                     [
                         my_scrolled_checks(C, M),
                         my_scrolled_checks(B, M),
                         my_scrolled_checks(A, M)
                     ]
                     ./\ clock(T)
                     ./\ intercepter(LastEvent)
                     ./\ quit((X-Y)-M)
        ).

tui:alias_drawable(quit(_), View) :-
    View = style([bg('#FFF')], "Quit").

tui:at_event_is(quit(M), ' ', result(M)).

tui:alias_drawable(intercepter(LastEvent), View) :-
    View = style([bg('#EEE')],
                 titled_frame(30-3, "Event", '"' .> literal(LastEvent) .> '"')).

tui:alias_drawable(clock(T), View) :-
    View = style([bg('#FFF')], titled_frame(10-3, "Time", T)).

tui:alias_drawable(my_scrolled_checks(Id, M), View) :-
    assocs_pairs(M,
                 [ moveable(Id)-MV,
                   scroll(Id)-SO,
                   checks-Checks
                 ]),
    moveable_style(Id, Style),
    View = moveable(Id) : moveable(MV,
              1-1-style(Style,
                        scroll(Id) : scroll(20-15, SO,
                           checks(Checks)
                        ))).

moveable_style(1, [fg(red)]).
moveable_style(2, [fg(green)]).
moveable_style(3, [fg(blue)]).

to_ided_checkbox(I, T, check_box(I) : check_box(L, T)) :- int_text(I, L).

tui:alias_drawable(checks(Checks), View) :-
    mapindexed(to_ided_checkbox, Checks, IndexedChecks),
    View = column(IndexedChecks).

list_index_is_updated([_|T], 1, H, [H|T]) :- !.
list_index_is_updated([H|T], N, Is, [H|U]) :-
    N > 1,
    Next is N - 1,
    list_index_is_updated(T, Next, Is, U).

tui:at_event_is(checks(Checks), check_box(I)-T, checks-Updated) :-
    list_index_is_updated(Checks, I, T, Updated).

% moveable
tui:alias_drawable(moveable(DX-DY-Moving, Drawable), View) :-
    (  Moving
    -> View = [
                  1-1-style([fg(black), bg(black)], translate(DX-DY, Drawable)),
                  0-0-style([faint], translate(DX-DY, Drawable))
              ]
    ;  View = translate(DX-DY, Drawable)
    ).

not(true, false).
not(false, true).

tui:at_event_is(moveable(DX-DY-Moving, _), ' ', moveable-(DX-DY-MovingToggle)) :-
    not(Moving, MovingToggle), !.

tui:at_event_is(moveable(DX-DY-true, _), moved(D, _, _), moveable-(DX1-DY1-true)) :-
    (   D = left, DX1 is DX - 1, DY1 is DY
    ;   D = right, DX1 is DX + 1, DY1 is DY
    ;   D = up, DX1 is DX, DY1 is DY - 1
    ;   D = down, DX1 is DX, DY1 is DY + 1
    ), !.

indent(X) :- write('  '), writeln(X).

go :-
    init(M),
    app(M, view, update, (X-Y)-Result),
    writeln("User Quit"),
    writeln("Last Model:"),
    writeln((X-Y)-'['),
    maplist(indent, Result),
    writeln(']').

