:- module(tui_utils,
          [
              goals_attempted/1,
              mapindexed/3,
              keylist_deduped_prioritize_last/2,
              capture//2,
              excluding//2,
              direction/1,
              limits_direction_from_to/4,
              limits_point_within/2
          ]).


'#cleanup'.

%!  goals_attempted(:Goals) is det.
%
%  Calls each goal of Goals once, in order, whatever the others do: a
%  goal that fails or throws is reported as a warning, and the rest are
%  still called. For cleanups, where every step should be tried.
:- meta_predicate(goals_attempted(:)).
goals_attempted(M:Goals) :-
    maplist(goal_attempted(M), Goals).

goal_attempted(M, Goal) :-
    catch(( call(M:Goal)
          ->  true
          ;   print_message(warning, tui_goal_failed(Goal))
          ),
          E,
          print_message(warning, tui_goal_raised(Goal, E))).

:- multifile prolog:message//1.

prolog:message(tui_goal_failed(Goal)) -->
    [ 'tui: goal failed: ~q'-[Goal] ].
prolog:message(tui_goal_raised(Goal, E)) -->
    [ 'tui: goal ~q raised: '-[Goal] ],
    prolog:translate_message(E).


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

% Sorted by key, keeping only the last pair for each key. sort/4 keeps
% the first of equal keys, which after reversing is the last.
keylist_deduped_prioritize_last(L0, LN) :-
    reverse(L0, R),
    sort(1, @<, R, LN).


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
