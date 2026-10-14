:- module(tui,
          [
            op(601, xfy, '.>'),
            op(601, xfy, '.<'),
            op(601, xfy, '.\\/'),
            op(601, xfy, './\\'),
            terminal_size/2,
            app/4
          ]).

/** <module> Text User Interface framework

A TUI framework for SWI-Prolog, inspired by TEA (The Elm Architecture).
Components are defined via the multifile hooks alias_drawable/2 and
at_event_is/3.

@author Mark Bolusmjak
@see app/4
*/

'#imports'.

:- use_module(library(unix)).
:- use_module(library(tui/utils)).
:- reexport(library(tui/utils), [direction/1, limits_direction_from_to/4]).
:- use_module(library(tui/terminal)).
:- reexport(library(tui/terminal), [wait_for_input/0, get_single_input/1]).
:- use_module(library(tui/drawable)).
:- reexport(library(tui/drawable), [drawable//5, drawable_raw/2]).
:- use_module(library(tui/hover)).
:- use_module(library(tui/events)).
:- reexport(library(tui/events), [stack_event_is/3]).
:- use_module(library(tui/components)).
:- use_module(library(ansi_term)).

%!  alias_drawable(+DrawableTerm, -ExpandedDrawable) is semidet.
%
%  Multifile hook. Define custom drawable components by mapping a term
%  to its drawable expansion. During rendering the alias is pushed onto
%  the component stack so that at_event_is/3 can intercept events.
%
%  @see at_event_is/3
:- multifile alias_drawable/2.

%!  at_event_is(+AliasOrStack, +RawEvent, -RewrittenEvent) is semidet.
%
%  Multifile hook. Rewrite an event as seen by a component on the alias
%  stack. Called during event bubbling: if the hook succeeds the event
%  is replaced; otherwise bubbling continues to the next stack entry.
%
%  @see stack_event_is/3
:- multifile at_event_is/3.


'#terminal_size'.

:- dynamic terminal_size_/2.

% IMPURE: mutable global — caches last-known terminal dimensions.
:- det(set_terminal_size__requires_redraw/3).
set_terminal_size__requires_redraw(Cols, Rows, Redraw) :-
    ignore(terminal_size_(PrevCols, PrevRows)),
    ignore(PrevCols = 0),
    retractall(terminal_size_(_, _)),
    asserta(terminal_size_(Cols, Rows)),
    (  PrevCols-PrevRows = Cols-Rows
    -> Redraw = false
    ;  ansi_reset,
       Redraw = true
    ).

%!  terminal_size(-Cols, -Rows) is det.
%
%  Current terminal dimensions in columns and rows.
%  Updated automatically on SIGWINCH.
:- det(terminal_size/2).
terminal_size(Cols, Rows) :-
    terminal_size_(Cols, Rows), !.


'#rendering'.

cursor_pred(Pred, (X1-Y1)-_, (X2-Y2)-_) :-
    compare(Pred, Y1-X1, Y2-X2).

% The frame's runs in standard order, with the cursor cell highlighted.
% The highlight is part of the cell's style, so the cursor cell forms its
% own run and moving the cursor changes the runs it touches.
limits_cursor_commands_runs(Limits, Cursor, Commands, Runs) :-
    include(limits_command_within(Limits), Commands, Onscreen),
    maplist(cursor_command_cell(Cursor), Onscreen, Cells0),
    predsort(cursor_pred, Cells0, Cells),
    once(phrase(grouped_by_attributes(Runs0), Cells)),
    msort(Runs0, Runs).

limits_command_within(Limits, XY-_) :-
    limits_point_within(Limits, XY).

cursor_command_cell(Cursor, (X-Y)-(_-A-C), (X-Y)-(Attrs-Char)) :-
    flatten(A, A1),
    raw_attributes_attributes(A1, A2),
    attributes_char_shown(A2, C, Attrs0, Char),
    (   Cursor = X-Y
    ->  append(Attrs0, [negative], Attrs)
    ;   Attrs = Attrs0
    ).

% IMPURE: draws the runs not already on screen. Runs within a frame never
% overlap, so a run in Previous is exactly what is at those cells.
previous_runs_rendered(Previous, Runs) :-
    ord_subtract(Runs, Previous, Changed),
    maplist(render_it, Changed).

render_it((X-Y)-(Style-Chars)) :-
    ansi_set_cursor(X, Y),
    ansi_format(Style, '~s', [Chars]).

% Runs of cells on the same row, at consecutive X, with equal attributes.
% Cells must be sorted row-major.
grouped_by_attributes([(X-Y)-(Attrs-[C | Cs]) | Runs]) -->
    [(X-Y)-(Attrs-C)],
    run_chars(X, Y, Attrs, Cs),
    grouped_by_attributes(Runs).
grouped_by_attributes([]) --> [].

run_chars(X0, Y, Attrs, [C | Cs]) -->
    { X is X0 + 1 },
    [(X-Y)-(Attrs-C)], !,
    run_chars(X, Y, Attrs, Cs).
run_chars(_, _, _, []) --> [].


'#app'.

:- det(tui_init/0).
tui_init :-
    ansi_reset,
    ansi_hide_cursor,
    retractall(terminal_size_(_, _)),
    tty_request_size,
    wait_for_terminal_size.

wait_for_terminal_size :-
    get_single_input(In),
    (  In = terminal_size(Cols, Rows)
    -> set_terminal_size__requires_redraw(Cols, Rows, _)
    ;  wait_for_terminal_size
    ).

%!  app(+State, :View, :Update, -Result) is det.
%
%  Run a TUI application. State is the initial (CursorX-CursorY)-Model.
%  View is called as call(View, State, Drawable) to produce the current
%  view. Update is called as call(Update, Event, State0, State1) to
%  handle events. The app exits with Result when an event bubbles to
%  result(Result), or when Update produces result(Result).
%
%  Everything runs in the calling thread, which must own the TTY. Other
%  threads deliver events through the wake pipe (see '#wake').
:- meta_predicate(app(?, 2, 3, ?)).
app(State, View, Update, Result) :-
    setup_call_cleanup(
        wake_open,
        with_tty_raw(
            (   tui_init,
                on_signal(winch, _, sig_winch),
                app_loop(app(View, Update), State, display(stale, []), Result)
            )
        ),
        (   @ on_signal(winch, _, default),
            @ wake_close,
            @ ansi_reset,
            @ ansi_show_cursor
        )
    ).

% Runs in the main thread, possibly mid-render, so it must not write to
% the terminal. The loop issues the size request instead.
sig_winch(_) :-
    post(terminal_resized).


'#wake'.

% Other threads (and signal handlers) queue an event, then write a byte
% to the wake pipe. The loop waits on the pipe alongside user_input.

% IMPURE: mutable global — the running app's event queue and wake pipe.
:- dynamic wake_/3.

wake_open :-
    pipe(In, Out),
    message_queue_create(Queue),
    asserta(wake_(Queue, In, Out)).

wake_close :-
    retract(wake_(Queue, In, Out)), !,
    close(In),
    close(Out),
    message_queue_destroy(Queue).

% IMPURE: queue Event for the running app and wake its loop. The event is
% queued before the byte is written; posted_events/1 relies on this.
post(Event) :-
    wake_(Queue, _, Out), !,
    thread_send_message(Queue, Event),
    put_char(Out, w),
    flush_output(Out).

% IMPURE: consume wake bytes, then drain the queue. Every byte consumed
% belongs to an event already queued, so none is left behind.
posted_events(Events) :-
    wake_(Queue, In, _), !,
    fill_buffer(In),
    read_pending_codes(In, _, []),
    queue_events(Queue, Events).

queue_events(Queue, Events) :-
    (   thread_get_message(Queue, E, [timeout(0)])
    ->  Events = [E | Es],
        queue_events(Queue, Es)
    ;   Events = []
    ).


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
% The display is display(Tracked, Runs), where Runs are the sorted runs
% currently on screen. Painting draws only runs not already there.

app_loop(App, State0, Display0, Result) :-
    App = app(View, _),
    view_state_display_painted(View, State0, Display0, Display1),
    ready_events(Events),
    app_events_state_display_outcome(App, Events, State0, Display1, Outcome),
    (   Outcome = result(Result)
    ->  true
    ;   Outcome = continue(State, Display),
        app_loop(App, State, Display, Result)
    ).

% IMPURE: blocks until input or a wake, then returns everything ready.
ready_events(Events) :-
    wake_(_, WakeIn, _), !,
    wait_for_input([user_input, WakeIn], Ready, infinite),
    (   memberchk(WakeIn, Ready)
    ->  posted_events(Posted)
    ;   Posted = []
    ),
    (   memberchk(user_input, Ready)
    ->  tty_events(Inputs)
    ;   Inputs = []
    ),
    append(Posted, Inputs, Events).

% IMPURE: one input, plus any others available without blocking.
tty_events([In | Ins]) :-
    get_single_input(In),
    (   wait_for_input([user_input], [_], 0)
    ->  tty_events(Ins)
    ;   Ins = []
    ).

app_events_state_display_outcome(_, [], State, Display, continue(State, Display)).
app_events_state_display_outcome(App, [E | Es], State0, Display0, Outcome) :-
    app_event_state_display_next(App, E, State0, Display0, Next),
    (   Next = result(_)
    ->  Outcome = Next
    ;   Next = continue(State1, Display1),
        app_events_state_display_outcome(App, Es, State1, Display1, Outcome)
    ).

% Framework events. A redraw means the terminal was reset: nothing is on
% screen.
app_event_state_display_next(_, terminal_resized, S, D, continue(S, D)) :- !,
    tty_request_size.
app_event_state_display_next(_, terminal_size(Cols, Rows), S, D0, continue(S, D)) :- !,
    set_terminal_size__requires_redraw(Cols, Rows, Redraw),
    (   Redraw
    ->  D = display(stale, [])
    ;   D = D0
    ).
% App events.
app_event_state_display_next(App, E, S0, display(T0, Runs), Next) :-
    App = app(View, Update),
    view_state_tracked_fresh(View, S0, T0, T1),
    tracked_frame(T1, Frame),
    frame_update_event_state0_state(Frame, Update, E, S0, S),
    (   S = result(_)
    ->  Next = S
    ;   S == S0
    ->  Next = continue(S0, display(T1, Runs))
    ;   Next = continue(S, display(stale, Runs))
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

view_state_tracked_fresh(View, State, stale, fresh(F)) :- !,
    view_state_frame(View, State, F).
view_state_tracked_fresh(_, _, T, T).

% IMPURE: paints the frame unless it is already on screen.
view_state_display_painted(_, _, D, D) :-
    D = display(painted(_), _), !.
view_state_display_painted(View, State, display(T0, Previous), display(painted(F), Runs)) :-
    view_state_tracked_fresh(View, State, T0, fresh(F)),
    (X-Y)-_ = State,
    F = frame(Commands, _, _),
    tty_render(X-Y, Commands, Previous, Runs).

view_state_frame(View, State, frame(Commands, EventAssoc, Extent)) :-
    (X-Y)-_ = State,
    call(View, State, Drawable),
    drawable__normalized_commands__end(Drawable, Commands, Extent),
    once(apply_focus(X-Y, Commands)),
    terminal_size(Cols, Rows),
    limits_commands_eventmap(Cols-Rows, Commands, EventMap),
    list_to_assoc(EventMap, EventAssoc).

tty_render(Cursor, Commands, Previous, Runs) :-
    ansi_hide_cursor,
    terminal_size(Cols, Rows),
    limits_cursor_commands_runs(Cols-Rows, Cursor, Commands, Runs),
    previous_runs_rendered(Previous, Runs),
    flush_output.
