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
:- use_module(library(tui/image)).
:- use_module(library(option)).


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
%  shortly after the start: program(Program) (TERM_PROGRAM, or unknown),
%  extended_keys(Bool) and graphics(Bool) (whether image/3 can be shown),
%  in no guaranteed order. With mouse(true) (see app/5), it receives
%  mouse events too.
%
%  Everything runs in the calling thread, which must own the TTY. Other
%  threads deliver events through a wake (see tui/wake.pl).
:- meta_predicate(app(?, 2, 3, ?)).
app(State, View, Update, Result) :-
    app(State, View, Update, Result, []).

%!  app(+State, :View, :Update, -Result, +Options) is det.
%
%  As app/4, with Options:
%
%    * mouse(Bool)
%      Whether the terminal reports the mouse (default false). Mouse
%      events, (X-Y)-mouse(Action, Button) (see tui/input.pl), bubble at
%      their own position rather than the cursor's, and a press moves
%      the cursor there. While on, the terminal's own text selection
%      needs a modifier, usually shift.
%    * substrate(Substrate)
%      Run on Substrate instead of the terminal; vcr(Script) replays a
%      script, for headless tests (see tui/vcr.pl). Terminal options,
%      such as mouse(Bool), then have no effect.
:- meta_predicate(app(?, 2, 3, ?, +)).
app(State, View, Update, Result, Options) :-
    (   option(substrate(Substrate), Options)
    ->  true
    ;   terminal_substrate(Options, Substrate)
    ),
    app_substrate(Substrate, State, View, Update, Result).

app_substrate(Substrate, State, View, Update, Result) :-
    setup_call_cleanup(
        (   wake_open(Wake),
            asserta(app_wake_(Wake))
        ),
        substrate_session(
            Substrate,
            Wake,
            app_loop(app(View, Update, Wake), State,
                     display(Substrate, stale, unknown, [], []), Result)
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
% Extent, Cursor, Images). The loop tracks it as stale (not computed),
% fresh(Frame) (computed, not on screen), or painted(Frame). Events are
% routed through the frame of the state they apply to, so a batch of
% events may compute several frames but paints only the last.
%
% Cursor is where the cursor is in the frame: the top-left cell drawn by
% cursor(_) if the view drew one, otherwise the state's cursor if update
% bound it, otherwise none. With no cursor nothing is highlighted, and
% events bubble through no components.
%
% Images are the image(Id, Source, W-H) drawn on screen, found on the
% stacks of their cells (see tui/image.pl).
%
% The display is display(Substrate, Tracked, Size, Runs, Images). Size is
% Cols-Rows, or unknown until the substrate reports it; nothing is
% painted before then. Runs are the sorted runs currently on the
% substrate. Painting draws only runs not already there. Images are
% those the substrate has been sent; painting sends only what is missing.
% A clear forgets them too, in case clearing deletes them.

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
wake_display_events(Wake, display(S0, T, Size, Runs, Is), Events, display(S, T, Size, Runs, Is)) :-
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
    D0 = display(Sub0, _, Size, _, _),
    (   Size == Cols-Rows
    ->  D = D0
    ;   substrate_cleared(Sub0, Sub),
        D = display(Sub, stale, Cols-Rows, [], [])
    ),
    app_event_state_display_updated(App, terminal_size(Cols, Rows), S, D, Next).
app_event_state_display_next(App, E, S0, D, Next) :-
    app_event_state_display_updated(App, E, S0, D, Next).

app_event_state_display_updated(App, E, S0, display(Sub, T0, Size, Runs, Is), Next) :-
    App = app(View, Update, _),
    view_size_state_tracked_fresh(View, Size, S0, T0, T1),
    tracked_frame(T1, Frame),
    frame_state_shown(Frame, S0, Shown),
    frame_update_event_state0_state(Frame, Update, E, Shown, S),
    (   S = result(_)
    ->  Next = S
    ;   S == Shown
    ->  Next = continue(Shown, display(Sub, T1, Size, Runs, Is))
    ;   Next = continue(S, display(Sub, stale, Size, Runs, Is))
    ).

% The state as shown: with the frame's cursor, which the view may have
% placed. Update receives this state.
frame_state_shown(frame(_, _, _, Cursor, _), Cursor0-Model, Shown) :-
    (   Cursor == none
    ->  Shown = Cursor0-Model
    ;   Shown = Cursor-Model
    ).

% The state an event leads to, or result(R). The event bubbles through
% the component stack under the cursor; each event it becomes, in order,
% is either a cursor movement (a direction, cursor_by(DX-DY)), handled
% here, or passed to Update. All are routed through Frame, the frame the
% event arrived at.
%
% A mouse event, (X-Y)-Mouse, bubbles at X-Y instead, as Mouse. A press
% first moves the cursor there, if there is one. What it becomes goes to
% Update; if it is still the mouse event, with its position.
:- meta_predicate frame_update_event_state0_state(+, 3, +, +, -).
frame_update_event_state0_state(Frame, Update, E0, S0, S) :-
    Frame = frame(_, EventAssoc, _, Cursor, _),
    (   E0 = XY-Mouse,
        mouse_event(Mouse, Action)
    ->  findall(E1, point_event_assoc_bubbled(XY, Mouse, EventAssoc, E1), Es0),
        maplist(mouse_bubbled_positioned(XY, Mouse), Es0, Es),
        action_point_state0_state(Action, XY, S0, S1),
        frame_update_bubbled_state0_state(Frame, Update, E0, Es, S1, S)
    ;   findall(E1, point_event_assoc_bubbled(Cursor, E0, EventAssoc, E1), Es),
        frame_update_bubbled_state0_state(Frame, Update, E0, Es, S0, S)
    ).

mouse_event(mouse(Action, _), Action).
mouse_event(_+M, Action) :-
    mouse_event(M, Action).

mouse_bubbled_positioned(XY, Mouse, E, Positioned) :-
    (   E == Mouse
    ->  Positioned = XY-Mouse
    ;   Positioned = E
    ).

action_point_state0_state(press, XY, C-Model, S) :-
    ground(C), !,
    S = XY-Model.
action_point_state0_state(_, _, S, S).

% Each event the raw event E0 became; those still equal to E0 are
% unclaimed.
:- meta_predicate frame_update_bubbled_state0_state(+, 3, +, +, +, -).
frame_update_bubbled_state0_state(_, _, _, [], S, S).
frame_update_bubbled_state0_state(Frame, Update, E0, [E | Es], S0, S) :-
    (   E == E0
    ->  Unclaimed = true
    ;   Unclaimed = false
    ),
    frame_update_one_state0_state(Frame, Update, Unclaimed, E, S0, S1),
    (   S1 = result(_)
    ->  S = S1
    ;   frame_update_bubbled_state0_state(Frame, Update, E0, Es, S1, S)
    ).

% A direction moves the cursor, if there is one, within the frame's
% extent. moved(Dir) then bubbles at the cursor's old position, and, for
% an arrow key no component claimed, arrived(Dir) at the new one. What
% they become, other than themselves, is handled with the cursor moved.
% A direction a component produced bubbles no arrived(Dir): its frame
% may predate the update it follows (an edit, say). cursor_by(DX-DY)
% moves the cursor by DX-DY, bubbling nothing. noop is dropped.
:- meta_predicate frame_update_one_state0_state(+, 3, +, +, +, -).
frame_update_one_state0_state(frame(_, EventAssoc, Extent, _, _), Update, Unclaimed, E, S0, S) :-
    (   E = result(_)
    ->  S = E
    ;   E == noop
    ->  S = S0
    ;   E = cursor_by(Offset)
    ->  extent_offset_state0_state(Extent, Offset, S0, S)
    ;   direction(E),
        S0 = (X-Y)-Model0,
        ground(X-Y)
    ->  limits_direction_from_to(Extent, E, X-Y, NX-NY),
        (   X-Y = NX-NY
        ->  S = S0
        ;   findall(E2, point_event_assoc_bubbled(X-Y, moved(E), EventAssoc, E2), E2s),
            exclude(==(moved(E)), E2s, Moved),
            (   Unclaimed == true
            ->  findall(E3, point_event_assoc_bubbled(NX-NY, arrived(E), EventAssoc, E3), E3s),
                exclude(==(arrived(E)), E3s, Arrived)
            ;   Arrived = []
            ),
            append(Moved, Arrived, Claimed),
            update_events_state0_state(Extent, Update, Claimed, (NX-NY)-Model0, S)
        )
    ;   call(Update, E, S0, S)
    ).

:- meta_predicate update_events_state0_state(+, 3, +, +, -).
update_events_state0_state(_, _, [], S, S).
update_events_state0_state(Extent, Update, [E | Es], S0, S) :-
    (   E = result(_)
    ->  S = E
    ;   (   E = cursor_by(Offset)
        ->  extent_offset_state0_state(Extent, Offset, S0, S1)
        ;   E == noop
        ->  S1 = S0
        ;   call(Update, E, S0, S1)
        ),
        (   S1 = result(_)
        ->  S = S1
        ;   update_events_state0_state(Extent, Update, Es, S1, S)
        )
    ).

% The cursor moved by DX-DY, staying within the extent (the frame is
% drawn from 1-1). Without a cursor, nothing moves.
extent_offset_state0_state(EX-EY, DX-DY, (X-Y)-Model, S) :-
    ground(X-Y), !,
    NX is max(1, min(EX, X + DX)),
    NY is max(1, min(EY, Y + DY)),
    S = (NX-NY)-Model.
extent_offset_state0_state(_, _, S, S).


'#frames'.

tracked_frame(fresh(F), F).
tracked_frame(painted(F), F).

view_size_state_tracked_fresh(View, Size, State, stale, fresh(F)) :- !,
    view_size_state_frame(View, Size, State, F).
view_size_state_tracked_fresh(_, _, _, T, T).

% IMPURE: paints the frame unless it is already on the substrate, or the
% substrate's size is not yet known.
view_state_display_painted(_, _, D, D) :-
    D = display(_, painted(_), _, _, _), !.
view_state_display_painted(_, _, D, D) :-
    D = display(_, _, unknown, _, _), !.
view_state_display_painted(View, State,
                           display(Sub0, T0, Size, Previous, Sent0),
                           display(Sub, painted(F), Size, Runs, Sent)) :-
    view_size_state_tracked_fresh(View, Size, State, T0, fresh(F)),
    F = frame(Commands, _, _, Cursor, Images),
    images_sent_actions(Images, Sent0, Actions, Sent),
    substrate_graphics_sent(Sub0, Actions, Sub1),
    limits_cursor_commands_runs(Size, Cursor, Commands, Runs),
    runs_previous_changed(Runs, Previous, Changed),
    substrate_runs_painted(Sub1, Changed, Sub).

view_size_state_frame(View, Size, State, frame(Commands, EventAssoc, Extent, Cursor, Images)) :-
    call(View, State, Drawable0),
    size_drawable_zoned(Size, Drawable0, Drawable),
    drawable__normalized_commands__end(Drawable, Commands, Extent),
    size_limits(Size, Limits),
    limits_commands_eventmap(Limits, Commands, EventMap),
    state_eventmap_cursor(State, EventMap, Cursor),
    limits_commands_images(Limits, Commands, Images),
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

% The images with a cell on screen. Every placeholder starts with
% U+10EEEE, above any other character in use, so one comparison rules
% out ordinary cells; only placeholders have their stacks searched.
% findall/3 copies, and every cell of an image holds its Source, so only
% the Ids are collected; each image is then taken, uncopied, from one of
% its cells.
limits_commands_images(Limits, Commands, Images) :-
    findall(Id, ( member(XY-(Stack-_-C), Commands),
                  C @> '\U0010EEED',
                  limits_point_within(Limits, XY),
                  memberchk(_-image(Id, _, _), Stack) ), Ids0),
    sort(Ids0, Ids),
    maplist(commands_id_image(Commands), Ids, Images).

commands_id_image(Commands, Id, image(Id, S, WH)) :-
    once(( member(_-(Stack-_-C), Commands),
           C @> '\U0010EEED',
           memberchk(_-image(Id, S, WH), Stack) )).

% Before the size is known, events may land anywhere.
size_limits(unknown, inf-inf) :- !.
size_limits(Size, Size).
