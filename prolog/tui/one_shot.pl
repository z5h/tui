:- module(tui_one_shot,
          [one_shot_message/2
          ]
).

%!  one_shot_message(-Var, -WakeStream) is det.
%
%  Create a one-shot inter-thread communication channel that can wake
%  a thread blocked on `wait_for_input/3`.
%
%  # Problem
%
%  In SWI-Prolog, `wait_for_input/3` on `user_input` only works from
%  the thread that owns the TTY (typically the main thread). Spawned
%  threads cannot reliably wait on terminal input — `wait_for_input`
%  blocks indefinitely regardless of keypresses.
%
%  This means the main thread must be the one calling `wait_for_input`.
%  But if the main thread is blocked waiting for user input, how can
%  another thread (e.g., an update/worker thread) signal that the
%  application should terminate?
%
%  Message queues alone don't solve this: `thread_peek_message/2`
%  doesn't block, so the main thread would need to poll. And
%  `thread_get_message/2` blocks but can't be combined with
%  `wait_for_input/3` — you can't wait on both simultaneously.
%
%  # Solution
%
%  Unix pipes provide file descriptors that `wait_for_input/3` *can*
%  monitor alongside `user_input`. Combined with `freeze/2`, we create
%  a channel where unifying a variable triggers a write to the pipe,
%  waking any thread blocked on the read end.
%
%  # How It Works
%
%  1. `pipe(ReadStream, WriteStream)` creates a Unix pipe — two
%     connected streams where writes to one appear as reads on the other.
%
%  2. `freeze(Var, Goal)` attaches Goal to Var. The goal remains
%     dormant until Var is unified with a non-variable term.
%
%  3. When Var is unified, the frozen goal fires: it writes the bound
%     value to WriteStream (as a canonical Prolog term), flushes, and
%     closes the write end.
%
%  4. The receiver includes WakeStream in its `wait_for_input/3` call.
%     When data arrives (because the freeze fired), the stream becomes
%     ready. The receiver reads the term and closes the read end.
%
%  # Usage
%
%  ```prolog
%  % Setup: create the channel
%  one_shot_message(Done, WakeStream),
%  
%  % Pass Done to worker thread (e.g., via thread_create or closure)
%  thread_create(worker(Done), _, []),
%  
%  % Main thread: wait on both TTY and wake signal
%  wait_for_input([user_input, WakeStream], Ready, infinite),
%  (   memberchk(WakeStream, Ready)
%  ->  read(WakeStream, Result),
%      close(WakeStream)
%      % Result is whatever Done was unified with
%  ;   memberchk(user_input, Ready)
%  ->  % handle user input...
%  ).
%  
%  % In worker thread, when done:
%  Done = my_result(Data)   % Fires freeze, wakes main thread
%  ```
%
%  # Constraints
%
%  - **One-shot**: The variable can only be unified once, and the
%    write end is closed after. For repeated signaling, create new
%    channels or use a different mechanism.
%
%  - **Unix-only**: Relies on `pipe/2` from `library(unix)`. This is
%    acceptable for TUI applications, which are inherently terminal-
%    oriented and rarely target Windows.
%
%  - **Ownership**: The write end is captured in the freeze closure.
%    The read end is returned to the caller, who is responsible for
%    closing it after reading.
%
%  @arg Var       An unbound variable. When unified, its value is sent
%                 through the pipe.
%  @arg WakeStream  A read stream that becomes ready when Var is bound.
%                 Caller should `read/2` from it to retrieve the value,
%                 then `close/1` it.
%
%  @see freeze/2, pipe/2, wait_for_input/3
one_shot_message(Var, ReadStream) :-
    pipe(ReadStream, WriteStream),
    freeze(Var,
           (   write_canonical(WriteStream, Var),
               write(WriteStream, '.\n'),
               flush_output(WriteStream),
               close(WriteStream)
           )).
