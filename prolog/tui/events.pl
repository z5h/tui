:- module(tui_events,
          [
            stack_event_is/3,
            point_event_assoc_bubbled/4,
            limits_commands_eventmap/3
          ]).

/** <module> Event bubbling

Events at a screen point bubble through the stack of components drawn
there, each of which may rewrite the event via tui:at_event_is/3. A
component sees where the event happened relative to its origin.
*/

:- use_module(library(tui/utils)).


'#bubbling'.

%!  stack_event_is(+Stack, +PositionedEvent, -BubbledEvent) is multi.
%
%  Walk the component Stack, entries Origin-Alias, from innermost to
%  outermost. PositionedEvent is X-Y-RawEvent. Each component sees the
%  event at X-Y relative to its
%  origin, RX-RY-RawEvent, and may rewrite it via at_event_is/3, once or
%  in several ways; each rewrite bubbles on from the same component. The
%  bottom of the stack, [], sees X-Y-RawEvent. If no component rewrites
%  the event, BubbledEvent = RawEvent. A rewrite to noop (the component
%  takes the event, to do nothing) bubbles no further.
stack_event_is(Stack, (X-Y)-E, Is) :-
    point_stack_event_is(X-Y, Stack, E, Is).

% As stack_event_is/3, at Point, which is X-Y or none. With no point,
% the bottom of the stack sees the event bare.
point_stack_event_is(_, V, _, _) :- var(V), domain_error(stack_event_is, stack:V).
point_stack_event_is(_, _, V, _) :- var(V), domain_error(stack_event_is, event:V).
point_stack_event_is(X-Y, [(OX-OY)-A | T], E, Is) :- !,
    RX is X - OX,
    RY is Y - OY,
    (   tui:at_event_is(A, (RX-RY)-E, Next)
    *-> next_stack_event_is(Next, X-Y, [(OX-OY)-A | T], Is)
    ;   point_stack_event_is(X-Y, T, E, Is)
    ).
point_stack_event_is(Point, [], E, Is) :- !,
    point_event_positioned(Point, E, PE),
    (   tui:at_event_is([], PE, Next)
    *-> next_stack_event_is(Next, Point, [], Is)
    ;   Is = E
    ).

% noop, a component taking an event to do nothing, bubbles no further.
next_stack_event_is(noop, _, _, noop) :- !.
next_stack_event_is(Next, Point, Stack, Is) :-
    point_stack_event_is(Point, Stack, Next, Is).

point_event_positioned(none, E, E).
point_event_positioned(X-Y, E, (X-Y)-E).

%!  point_event_assoc_bubbled(+Point, +E0, +EventAssoc, -E1) is multi.
%
%  E1 is what E0 becomes as it bubbles through the stack at Point (X-Y,
%  or none for no cursor).
point_event_assoc_bubbled(none, E0, _, E1) :- !,
    point_stack_event_is(none, [], E0, E1).
point_event_assoc_bubbled(X-Y, E0, EventAssoc, E1) :-
    (  get_assoc(X-Y, EventAssoc, Stack)
    -> true
    ;  Stack = []
    ),
    point_stack_event_is(X-Y, Stack, E0, E1).


'#event_map'.

%!  limits_commands_eventmap(+Limits, +Commands, -EventMap) is det.
%
%  EventMap holds Point-Stack for every command within Limits: which
%  components were drawn at each point, for bubbling.
limits_commands_eventmap(_, [], []).
limits_commands_eventmap(Limits, [((X-Y)-(S-_-_))|T], EM) :-
    (  limits_point_within(Limits, X-Y)
    -> E = (X-Y)-S,
       EM = [E|EMT]
    ;  EM = EMT
    ),
    limits_commands_eventmap(Limits, T, EMT).
