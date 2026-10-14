:- module(tui_events,
          [
            stack_event_is/3,
            point_event_assoc_bubbled/4,
            limits_commands_eventmap/3
          ]).

/** <module> Event bubbling

Events at a screen point bubble through the stack of components drawn
there, each of which may rewrite the event via tui:at_event_is/3.
*/

:- use_module(library(tui/utils)).


'#bubbling'.

%!  stack_event_is(+Stack, +RawEvent, -BubbledEvent) is det.
%
%  Walk the component Stack from innermost to outermost, giving each
%  component a chance to rewrite the event via at_event_is/3. If no
%  component rewrites the event, BubbledEvent = RawEvent.
stack_event_is(V, _, _) :- var(V), domain_error(stack_event_is, stack:V).
stack_event_is(_, V, _) :- var(V), domain_error(stack_event_is, event:V).
stack_event_is([H|T], E, Is) :- !,
    (  tui:at_event_is(H, E, Next)
    -> stack_event_is([H|T], Next, Is)
    ;  stack_event_is(T, E, Is)
    ).
stack_event_is([], E, Is) :- !,
    (  tui:at_event_is([], E, Next)
    -> stack_event_is([], Next, Is)
    ;  Is = E
    ).

% The event E0 becomes as it bubbles through the stack at point X-Y.
point_event_assoc_bubbled(X-Y, E0, EventAssoc, E1) :-
    (  get_assoc(X-Y, EventAssoc, Stack)
    -> true
    ;  Stack = []
    ),
    stack_event_is(Stack, E0, E1).


'#event_map'.

% Point-Stack pairs for every command within Limits.
limits_commands_eventmap(_, [], []).
limits_commands_eventmap(Limits, [((X-Y)-(S-_-_))|T], EM) :-
    (  limits_point_within(Limits, X-Y)
    -> E = (X-Y)-S,
       EM = [E|EMT]
    ;  EM = EMT
    ),
    limits_commands_eventmap(Limits, T, EMT).
