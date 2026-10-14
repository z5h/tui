:- module(tui_loop,
          [
            app/4,
            app/5
          ]).

/** <module> Event loop

Runs an app: paints its view onto a substrate, folds events through
bubbling and the app's update, and repeats until a result.
*/

:- use_module(library(tui/utils)).
:- use_module(library(tui/drawable)).
:- use_module(library(tui/hover)).
:- use_module(library(tui/events)).
:- use_module(library(tui/render)).
:- use_module(library(tui/wake)).
:- use_module(library(tui/substrate)).


'#app'.

%!  app(+State, :View, :Update, -Result) is det.
%
%  Run a TUI application. State is the initial (CursorX-CursorY)-Model.
%  View is called as call(View, State, Drawable) to produce the current
%  view. Update is called as call(Update, Event, State0, State1) to
%  handle events. The app exits with Result when an event bubbles to
%  result(Result), or when Update produces result(Result).
%
%  Everything runs in the calling thread, which must own the TTY. Other
%  threads deliver events through a wake (see tui/wake.pl).
:- meta_predicate(app(?, 2, 3, ?)).
app(State, View, Update, Result) :-
    terminal_substrate(Substrate),
    app(Substrate, State, View, Update, Result).

%  app(+Substrate, +State, :View, :Update, -Result)
%
%  As app/4, on Substrate (see tui/substrate.pl).
:- meta_predicate(app(+, ?, 2, 3, ?)).
app(Substrate, State, View, Update, Result) :-
    setup_call_cleanup(
        (   wake_open(Wake),
            asserta(app_wake_(Wake))
        ),
        substrate_session(
            Substrate,
            Wake,
            app_loop(app(View, Update, Wake), State,
                     display(Substrate, stale, unknown, []), Result)
        ),
        (   @ retract(app_wake_(Wake)),
            @ wake_close(Wake)
        )
    ).


'#posting'.

% IMPURE: mutable global — the running app's wake, for senders that have
% no other way to reach it (other threads).
:- dynamic app_wake_/1.

% IMPURE: deliver Event to the running app.
post(Event) :-
    app_wake_(Wake), !,
    wake_post(Wake, Event).


'#loop'.

% Each iteration paints the current state if needed, waits, then folds
% every ready event into the state before painting again.
%
% A frame is the rendered form of a state: frame(Commands, EventAssoc,
% Extent). The loop tracks it as stale (not computed), fresh(Frame)
% (computed, not on screen), or painted(Frame). Events are routed
% through the frame of the state they apply to, so a batch of events
% may compute several frames but paints only the last.
%
% The display is display(Substrate, Tracked, Size, Runs). Size is Cols-Rows,
% or unknown until the substrate reports it; nothing is painted before
% then. Runs are the sorted runs currently on the substrate. Painting
% draws only runs not already there.

app_loop(App, State0, Display0, Result) :-
    App = app(View, _, Wake),
    view_state_display_painted(View, State0, Display0, Display1),
    wake_display_events(Wake, Display1, Events, Display2),
    app_events_state_display_outcome(App, Events, State0, Display2, Outcome),
    (   Outcome = result(Result)
    ->  true
    ;   Outcome = continue(State, Display),
        app_loop(App, State, Display, Result)
    ).

% IMPURE: blocks until the substrate has events.
wake_display_events(Wake, display(S0, T, Size, Runs), Events, display(S, T, Size, Runs)) :-
    substrate_events(S0, Wake, Events, S).

app_events_state_display_outcome(_, [], State, Display, continue(State, Display)).
app_events_state_display_outcome(App, [E | Es], State0, Display0, Outcome) :-
    app_event_state_display_next(App, E, State0, Display0, Next),
    (   Next = result(_)
    ->  Outcome = Next
    ;   Next = continue(State1, Display1),
        app_events_state_display_outcome(App, Es, State1, Display1, Outcome)
    ).

% Framework events. A new size clears the substrate: nothing is on it.
app_event_state_display_next(_, terminal_size(Cols, Rows), S, D0, continue(S, D)) :- !,
    D0 = display(Sub0, _, Size, _),
    (   Size == Cols-Rows
    ->  D = D0
    ;   substrate_cleared(Sub0, Sub),
        D = display(Sub, stale, Cols-Rows, [])
    ).
% App events.
app_event_state_display_next(App, E, S0, display(Sub, T0, Size, Runs), Next) :-
    App = app(View, Update, _),
    view_size_state_tracked_fresh(View, Size, S0, T0, T1),
    tracked_frame(T1, Frame),
    frame_update_event_state0_state(Frame, Update, E, S0, S),
    (   S = result(_)
    ->  Next = S
    ;   S == S0
    ->  Next = continue(S0, display(Sub, T1, Size, Runs))
    ;   Next = continue(S, display(Sub, stale, Size, Runs))
    ).

% The state an event leads to, or result(R). Cursor movement is handled
% here; other events are bubbled through the component stack under the
% cursor and passed to Update.
:- meta_predicate frame_update_event_state0_state(+, 3, +, +, -).
frame_update_event_state0_state(frame(_, EventAssoc, Extent), Update, E0, S0, S) :-
    (X-Y)-Model0 = S0,
    point_event_assoc_bubbled(X-Y, E0, EventAssoc, E1),
    (   E1 = result(_)
    ->  S = E1
    ;   direction(E1)
    ->  limits_direction_from_to(Extent, E1, X-Y, NX-NY),
        (   X-Y = NX-NY
        ->  S = S0
        ;   point_event_assoc_bubbled(X-Y, moved(E1, X-Y, NX-NY), EventAssoc, E2),
            (   E2 = moved(E1, X-Y, NX-NY)
            ->  S = (NX-NY)-Model0
            ;   call(Update, E2, (NX-NY)-Model0, S)
            )
        )
    ;   call(Update, E1, S0, S)
    ).


'#frames'.

tracked_frame(fresh(F), F).
tracked_frame(painted(F), F).

view_size_state_tracked_fresh(View, Size, State, stale, fresh(F)) :- !,
    view_size_state_frame(View, Size, State, F).
view_size_state_tracked_fresh(_, _, _, T, T).

% IMPURE: paints the frame unless it is already on the substrate, or the
% substrate's size is not yet known.
view_state_display_painted(_, _, D, D) :-
    D = display(_, painted(_), _, _), !.
view_state_display_painted(_, _, D, D) :-
    D = display(_, _, unknown, _), !.
view_state_display_painted(View, State, display(Sub0, T0, Size, Previous), display(Sub, painted(F), Size, Runs)) :-
    view_size_state_tracked_fresh(View, Size, State, T0, fresh(F)),
    (X-Y)-_ = State,
    F = frame(Commands, _, _),
    limits_cursor_commands_runs(Size, X-Y, Commands, Runs),
    runs_previous_changed(Runs, Previous, Changed),
    substrate_runs_painted(Sub0, Changed, Sub).

view_size_state_frame(View, Size, State, frame(Commands, EventAssoc, Extent)) :-
    (X-Y)-_ = State,
    call(View, State, Drawable),
    drawable__normalized_commands__end(Drawable, Commands, Extent),
    once(apply_focus(X-Y, Commands)),
    size_limits(Size, Limits),
    limits_commands_eventmap(Limits, Commands, EventMap),
    list_to_assoc(EventMap, EventAssoc).

% Before the size is known, events may land anywhere.
size_limits(unknown, inf-inf) :- !.
size_limits(Size, Size).
