:- module(async, []).

/** <module> Async — events from other threads: ports and subscriptions

A timer and a worker thread, both declared as subscriptions: functions
of the state, like the view. The loop starts what the list gains and
stops what it loses.

  * every(1000, tick) counts seconds while the clock runs; t stops and
    restarts it, by taking the timer out of the list and back.
  * thread(worker) runs worker/1 in its own thread, given the app's
    port. The worker introduces itself with worker_ready(Thread); s
    sends it a job (update may send messages, but must not wait for an
    answer), and the worker reports progress as events.

    swipl tui run async
*/

:- use_module(library(tui)).

:- initialization(main, main).

main :-
    app(_-model(0, true, none, idle), view, update, _,
        [subscriptions(subscriptions)]).

% model(Seconds, Ticking, Worker, Job): Worker is none until the worker
% introduces itself; Job is idle, running(Done, Total) or done(Total).

subscriptions(_-model(_, Ticking, _, _), Subs) :-
    (   Ticking == true
    ->  Subs = [every(1000, tick), thread(worker)]
    ;   Subs = [thread(worker)]
    ).


'#worker'.

% Runs in its own thread. Jobs arrive as messages to the thread; their
% progress goes back to the app through its port.
worker(Port) :-
    thread_self(Me),
    port_send(Port, worker_ready(Me)),
    worker_jobs(Port).

worker_jobs(Port) :-
    thread_get_message(job(Total)),
    forall(between(1, Total, Done),
           (   sleep(0.1),
               port_send(Port, progress(Done, Total))
           )),
    worker_jobs(Port).


'#update'.

update(q, S, result(S)) :- !.
update(tick, C-model(N0, T, W, J), C-model(N, T, W, J)) :- !,
    N is N0 + 1.
update(t, C-model(N, T0, W, J), C-model(N, T, W, J)) :- !,
    not(T0, T).
update(worker_ready(W), C-model(N, T, _, J), C-model(N, T, W, J)) :- !.
update(s, C-model(N, T, W, J0), C-model(N, T, W, J)) :-
    W \== none,
    J0 \= running(_, _), !,
    thread_send_message(W, job(30)),
    J = running(0, 30).
update(progress(Total, Total), C-model(N, T, W, _), C-model(N, T, W, done(Total))) :- !.
update(progress(Done, Total), C-model(N, T, W, _), C-model(N, T, W, running(Done, Total))) :- !.
update(_, S, S).

not(true, false).
not(false, true).


'#view'.

view(_-model(N, T, W, J), column([ row(["Seconds: ", literal(N), "   ", Clock]),
                                   "",
                                   row(["Job: ", Job]),
                                   "",
                                   style([faint], Keys) ])) :-
    (   T == true
    ->  Clock = style([faint], "(running; t stops it)")
    ;   Clock = style([faint], "(stopped; t restarts it)")
    ),
    job_drawable(W, J, Job),
    Keys = "s starts a job, q quits".

job_drawable(none, _, "waiting for the worker").
job_drawable(W, idle, "idle") :- W \== none.
job_drawable(W, running(Done, Total), row([Bar, " ", literal(Done/Total)])) :-
    W \== none,
    done_total_bar(Done, Total, Bar).
job_drawable(W, done(Total), row([Bar, " done"])) :-
    W \== none,
    done_total_bar(Total, Total, Bar).

done_total_bar(Done, Total, chars(Chars)) :-
    Width = 30,
    Filled is Width * Done // Total,
    Empty is Width - Filled,
    length(F, Filled),
    maplist(=('#'), F),
    length(E, Empty),
    maplist(=('.'), E),
    append(F, E, Chars).
