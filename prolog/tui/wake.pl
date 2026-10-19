:- module(tui_wake,
          [
            wake_open/1,
            wake_close/1,
            wake_post/2,
            wake_stream/2,
            wake_events/2,
            wake_count_timeout_events/4
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

%!  wake_open(-Wake) is det.
%
%  IMPURE: Wake is a new wake: a message queue and a pipe.
wake_open(wake(Queue, In, Out)) :-
    pipe(In, Out),
    message_queue_create(Queue).

%!  wake_close(+Wake) is det.
%
%  IMPURE: closes Wake's pipe and destroys its queue. Posting to it
%  afterwards raises an existence error.
wake_close(wake(Queue, In, Out)) :-
    close(In),
    close(Out),
    message_queue_destroy(Queue).


'#posting'.

%!  wake_post(+Wake, +Event) is det.
%
%  IMPURE: queue Event and wake the waiting thread, from any thread. The
%  event is queued before the byte is written; wake_events/2 relies on
%  this.
wake_post(wake(Queue, _, Out), Event) :-
    thread_send_message(Queue, Event),
    put_char(Out, w),
    flush_output(Out).


'#waiting'.

%!  wake_stream(+Wake, -Stream) is det.
%
%  Stream is the stream to include in wait_for_input/3: it becomes
%  ready when an event is posted.
wake_stream(wake(_, In, _), In).

%!  wake_events(+Wake, -Events) is det.
%
%  IMPURE: consume wake bytes, then drain the queue into Events. Every
%  byte consumed belongs to an event already queued, so none is left
%  behind. Call only when the wake stream is ready, or it blocks.
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

%!  wake_count_timeout_events(+Wake, +N, +Timeout, -Events) is semidet.
%
%  IMPURE: blocks until N events have been posted, waiting at most
%  Timeout seconds for each, and takes them with their bytes. Fails on a
%  timeout. For headless tests, which wait for exactly what they expect.
wake_count_timeout_events(wake(Queue, In, _), N, Timeout, Events) :-
    length(Events, N),
    maplist(queue_timeout_event(Queue, Timeout), Events),
    length(Bytes, N),
    maplist(get_char(In), Bytes).

queue_timeout_event(Queue, Timeout, E) :-
    thread_get_message(Queue, E, [timeout(Timeout)]).
