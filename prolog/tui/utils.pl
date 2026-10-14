:- module(tui_utils,
          [
              op(950, fy, ?),
              op(950, fy, @),
              log/1,
              '?'/1,
              '@'/1,
              mapindexed/3,
              keylist_deduped_prioritize_last/2,
              capture//2,
              excluding//2,
              direction/1,
              limits_direction_from_to/4,
              limits_point_within/2
          ]).


'#debug'.

:- meta_predicate(log(0)).
log(Goal) :-
    setup_call_cleanup(
        open('tui.log', append, Out),
        (   with_output_to(Out, Goal),
            with_output_to(Out, nl)
        ),
        close(Out)
    ).

:- meta_predicate(debug_call(0)).
debug_call(G) :-
    (   G
    *-> log(writeln(pass:G))
    ;   log(writeln(fail:G)), fail
    ).

:- meta_predicate('?'(0)).
'?'(G) :- debug_call(G).

:- meta_predicate('@'(0)).
:- det('@'/1).
'@'(G) :- G.


'#lists'.

%!  mapindexed(:Goal, +List, -Mapped) is det.
%
%  Like maplist/3 but calls Goal with a 1-based index:
%  call(Goal, Index, Element, MappedElement) for each element.
:- meta_predicate mapindexed(3, ?, ?).
mapindexed(F, List, Mapped) :-
    function_list_from_mapped(F, List, 1, Mapped).

:- meta_predicate function_list_from_mapped(3, ?, ?, ?).
function_list_from_mapped(_, [], _, []).
function_list_from_mapped(F, [H  |T], I, [MH  |MT]) :-
    call(F, I, H, MH),
    J is I + 1,
    function_list_from_mapped(F, T, J, MT).

pair_key_pred(Delta, K1-_, K2-_) :- compare(Delta, K1, K2).

keylist_deduped_prioritize_last(L0, LN) :-
    reverse(L0, R),
    predsort(pair_key_pred, R, LN).


'#dcg'.

:- meta_predicate(capture(//, ?, ?, ?)).
capture(Phrase, C, A, A2) :-
    phrase(Phrase, C, []), !,
    A = A2.

:- meta_predicate(excluding(1, //, ?, ?)).
excluding(Pred, Phrase) -->
    capture(Phrase, C),
    { exclude(Pred, C, E) }, !,
    E.


'#navigation'.

%!  direction(+Event) is semidet.
%
%  True if Event is a directional input: up, down, left, or right.
direction(E) :- member(E, [up, down, left, right]).

%!  limits_direction_from_to(+Limits, +Direction, +From, -To) is det.
%
%  Compute the cursor position To by moving one step in Direction from
%  From, clamped to 1..Limits. Limits is MaxX-MaxY.
limits_direction_from_to(_-_, up, X-Y0, X-Y) :-
    Y is max(1, Y0 - 1).
limits_direction_from_to(_-_, left, X0-Y, X-Y) :-
    X is max(1, X0 - 1).
limits_direction_from_to(MX-_, right, X0-Y, X-Y) :-
    X is min(MX, X0 + 1).
limits_direction_from_to(_-MY, down, X-Y0, X-Y) :-
    Y is min(MY, Y0 + 1).

%!  limits_point_within(+Limits, +Point) is semidet.
%
%  True if Point X-Y lies within 1..Limits. Limits is MaxX-MaxY.
limits_point_within(MX-MY, X-Y) :-
    X > 0,
    Y > 0,
    X =< MX,
    Y =< MY.
