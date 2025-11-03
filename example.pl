:- module(example, [go/0
                   ]).

:- reexport(tui).
:- use_module(components).
:- use_module(local(core/core)).

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
    findall(N-true, between(1, 300, N), Checks).

init(M) :-
    init_checks(Cs),
    M =
        [ cursor-(1-1),
          checks-Cs,
          scroll_offset1-(0-0),
          scroll_offset2-(0-0),
          scroll_offset3-(0-0)

        ].

wait_for(V) :-
    \+ var(V), !.

wait_for(V) :- !,
    sleep(0),
    wait_for(V).

:- meta_predicate(trampoline_loop(2, ?)).
trampoline_loop(Pred, In) :-
    call_time(call(Pred, In, Out), T),
    append_output_to_file('bench.log', writeln(T)),
    wait_for(Out),
    trampoline_loop(Pred, Out).

app(M0, M1) :-
    assocs(M0 ~> M1) <-.. cursor-(C0 ~> C1),
    assocs(M0 ~> M1) <-.. scroll_offset1-(SO10 ~> SO11),
    assocs(M0 ~> M1) <-.. scroll_offset2-(SO20 ~> SO21),

    assocs(M0 ~> M1) <-.. checks-(CH0 ~> CH1),
    list(CH0 ~> CH1) <-.. CheckTriggers,

    maplist(checktrigger_check, CheckTriggers, Checks),


    View = titled_frame(80-21, "My App",
                        [style([fg(red)],
                               scroll(10-19, SO10 ~> SO11,
                                      column(Checks)
                               ))
                         .>
                             style([fg(green)],
                                   scroll(10-19, SO20 ~> SO21,
                                          column(Checks)
                                   )), style([hfg(blue)], 8-4-titled_frame(10-3, "Float", abc))
                        ]


           ),
    cursor_drawables_render(C0 ~> C1, View), !.

checktrigger_check(T, check(T)).

% check
alias_drawable(check((Id-Bool) ~> _), View) :-
    atomic_list_concat([Id], IdAtom),
    View = check_box(IdAtom, Bool).

at_event_is(check((Id-_) ~> CH1), toggle(T), goal(CH1 = Id-T)).

% scroll

go :-
    reset,
    tui_init,
    init(M),
    with_tty_raw(trampoline_loop(app, M)).
