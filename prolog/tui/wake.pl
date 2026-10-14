:- module(tui_wake,
          [
            wake_open/1,
            wake_close/1,
            wake_post/2,
            wake_stream/2,
            wake_events/2
          ]).

/** <module> Wakeable event queue

A message queue that a thread blocked in wait_for_input/3 can wait on.
Posting queues an event, then writes a byte to a pipe; the waiting
thread includes the pipe's read end in its wait_for_input/3 call.

A wake is the term wake(Queue, In, Out). Treat it as opaque. It may be
copied to other threads; the queue and streams it holds stay shared.
*/

:- use_module(library(unix)).


'#lifecycle'.

wake_open(wake(Queue, In, Out)) :-
    pipe(In, Out),
    message_queue_create(Queue).

wake_close(wake(Queue, In, Out)) :-
    close(In),
    close(Out),
    message_queue_destroy(Queue).


'#posting'.

% IMPURE: queue Event and wake the waiting thread. The event is queued
% before the byte is written; wake_events/2 relies on this.
wake_post(wake(Queue, _, Out), Event) :-
    thread_send_message(Queue, Event),
    put_char(Out, w),
    flush_output(Out).


'#waiting'.

% The stream to include in wait_for_input/3.
wake_stream(wake(_, In, _), In).

% IMPURE: consume wake bytes, then drain the queue. Every byte consumed
% belongs to an event already queued, so none is left behind. Call only
% when the wake stream is ready, or it blocks.
wake_events(wake(Queue, In, _), Events) :-
    fill_buffer(In),
    read_pending_codes(In, _, []),
    queue_events(Queue, Events).

queue_events(Queue, Events) :-
    (   thread_get_message(Queue, E, [timeout(0)])
    ->  Events = [E | Es],
        queue_events(Queue, Es)
    ;   Events = []
    ).
