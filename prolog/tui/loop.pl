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
%  Besides keys, Update receives terminal_size(Cols, Rows) at the start
%  and after every resize, and terminal_properties(Properties) once,
%  shortly after the start: program(Program) (TERM_PROGRAM, or unknown)
%  and extended_keys(Bool), in no guaranteed order.
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
% Extent, Cursor). The loop tracks it as stale (not computed),
% fresh(Frame) (computed, not on screen), or painted(Frame). Events are
% routed through the frame of the state they apply to, so a batch of
% events may compute several frames but paints only the last.
%
% Cursor is where the cursor is in the frame: the top-left cell drawn by
% cursor(_) if the view drew one, otherwise the state's cursor if update
% bound it, otherwise none. With no cursor nothing is highlighted, and
% events bubble through no components.
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

% A new size clears the substrate: nothing is on it. The app then gets
% the size like any other event, so it can lay itself out.
app_event_state_display_next(App, terminal_size(Cols, Rows), S, D0, Next) :- !,
    D0 = display(Sub0, _, Size, _),
    (   Size == Cols-Rows
    ->  D = D0
    ;   substrate_cleared(Sub0, Sub),
        D = display(Sub, stale, Cols-Rows, [])
    ),
    app_event_state_display_updated(App, terminal_size(Cols, Rows), S, D, Next).
app_event_state_display_next(App, E, S0, D, Next) :-
    app_event_state_display_updated(App, E, S0, D, Next).

app_event_state_display_updated(App, E, S0, display(Sub, T0, Size, Runs), Next) :-
    App = app(View, Update, _),
    view_size_state_tracked_fresh(View, Size, S0, T0, T1),
    tracked_frame(T1, Frame),
    frame_state_shown(Frame, S0, Shown),
    frame_update_event_state0_state(Frame, Update, E, Shown, S),
    (   S = result(_)
    ->  Next = S
    ;   S == Shown
    ->  Next = continue(Shown, display(Sub, T1, Size, Runs))
    ;   Next = continue(S, display(Sub, stale, Size, Runs))
    ).

% The state as shown: with the frame's cursor, which the view may have
% placed. Update receives this state.
frame_state_shown(frame(_, _, _, Cursor), Cursor0-Model, Shown) :-
    (   Cursor == none
    ->  Shown = Cursor0-Model
    ;   Shown = Cursor-Model
    ).

% The state an event leads to, or result(R). The event bubbles through
% the component stack under the cursor; each event it becomes, in order,
% is either a cursor movement, handled here, or passed to Update. All
% are routed through Frame, the frame the event arrived at.
:- meta_predicate frame_update_event_state0_state(+, 3, +, +, -).
frame_update_event_state0_state(Frame, Update, E0, S0, S) :-
    Frame = frame(_, EventAssoc, _, Cursor),
    findall(E1, point_event_assoc_bubbled(Cursor, E0, EventAssoc, E1), Es),
    frame_update_bubbled_state0_state(Frame, Update, Es, S0, S).

:- meta_predicate frame_update_bubbled_state0_state(+, 3, +, +, -).
frame_update_bubbled_state0_state(_, _, [], S, S).
frame_update_bubbled_state0_state(Frame, Update, [E | Es], S0, S) :-
    frame_update_one_state0_state(Frame, Update, E, S0, S1),
    (   S1 = result(_)
    ->  S = S1
    ;   frame_update_bubbled_state0_state(Frame, Update, Es, S1, S)
    ).

% A direction moves the cursor, if there is one, within the frame's
% extent. moved(Dir) then bubbles at the cursor's old position; what it
% becomes, if anything else, is passed to Update with the cursor moved.
:- meta_predicate frame_update_one_state0_state(+, 3, +, +, -).
frame_update_one_state0_state(frame(_, EventAssoc, Extent, _), Update, E, S0, S) :-
    (   E = result(_)
    ->  S = E
    ;   direction(E),
        S0 = (X-Y)-Model0,
        ground(X-Y)
    ->  limits_direction_from_to(Extent, E, X-Y, NX-NY),
        (   X-Y = NX-NY
        ->  S = S0
        ;   findall(E2, point_event_assoc_bubbled(X-Y, moved(E), EventAssoc, E2), E2s),
            exclude(==(moved(E)), E2s, Claimed),
            update_events_state0_state(Update, Claimed, (NX-NY)-Model0, S)
        )
    ;   call(Update, E, S0, S)
    ).

:- meta_predicate update_events_state0_state(3, +, +, -).
update_events_state0_state(_, [], S, S).
update_events_state0_state(Update, [E | Es], S0, S) :-
    (   E = result(_)
    ->  S = E
    ;   call(Update, E, S0, S1),
        (   S1 = result(_)
        ->  S = S1
        ;   update_events_state0_state(Update, Es, S1, S)
        )
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
    F = frame(Commands, _, _, Cursor),
    limits_cursor_commands_runs(Size, Cursor, Commands, Runs),
    runs_previous_changed(Runs, Previous, Changed),
    substrate_runs_painted(Sub0, Changed, Sub).

view_size_state_frame(View, Size, State, frame(Commands, EventAssoc, Extent, Cursor)) :-
    call(View, State, Drawable0),
    size_drawable_zoned(Size, Drawable0, Drawable),
    drawable__normalized_commands__end(Drawable, Commands, Extent),
    size_limits(Size, Limits),
    limits_commands_eventmap(Limits, Commands, EventMap),
    state_eventmap_cursor(State, EventMap, Cursor),
    (   Cursor = X-Y
    ->  once(apply_focus(X-Y, Commands))
    ;   true
    ),
    list_to_assoc(EventMap, EventAssoc).

% The view is drawn in a zone the size of the substrate, so that aligns
% at its top level align to the substrate's edges, and the cursor can
% move anywhere on it. Until the size is known, the view is drawn as is.
size_drawable_zoned(unknown, D, D).
size_drawable_zoned(Cols-Rows, D, zone(Cols-Rows, D)).

% The top-left cell drawn by cursor(_), if any; otherwise the state's
% cursor if update bound it; otherwise none.
state_eventmap_cursor(Cursor0-_, EventMap, Cursor) :-
    findall(Y-X, ( member((X-Y)-Stack, EventMap),
                   memberchk(_-cursor(_), Stack) ), Marked),
    (   Marked \== []
    ->  min_member(Y-X, Marked),
        Cursor = X-Y
    ;   ground(Cursor0)
    ->  Cursor = Cursor0
    ;   Cursor = none
    ).

% Before the size is known, events may land anywhere.
size_limits(unknown, inf-inf) :- !.
size_limits(Size, Size).
