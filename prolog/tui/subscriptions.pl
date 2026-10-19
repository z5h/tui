:- module(tui_subscriptions,
          [
            port_send/2,
            subscriptions_open/2,
            subscriptions_running/3,
            subscriptions_closed/1,
            running_subs_stopped_started/4
          ]).

/** <module> Ports and subscriptions

How events reach an app from other threads.

A port is the writing end of the app's event stream: port_send(Port,
Event) from any thread queues Event, and update receives it in turn.
Events from one sender arrive in order; those of several senders are
merged. Sending to the port of an app that has ended does nothing.

An app declares what should be sending to it as subscriptions, a list
computed from its state like its view (app/5 option subscriptions/1):

  * every(Ms, Event)
    Event every Ms milliseconds.
  * thread(Goal)
    call(Goal, Port) in a thread of its own. Goal may send any number of
    events. If it ends by itself, update receives thread_ended(Goal,
    Status), Status being true, false or exception(E).

A subscription is identified by its term. After each update, a term
still in the list keeps running, a new one is started, and one no longer
in the list is stopped, as are all when the app ends. Stopping throws
tui_stop in the subscription's thread, which unwinds it (running its
cleanups); a goal that catches every exception should rethrow tui_stop.
Events it sent before stopping may still arrive.
*/

:- use_module(library(apply)).
:- use_module(library(error)).
:- use_module(library(lists)).
:- use_module(library(tui/wake)).


'#ports'.

%!  port_send(+Port, +Event) is det.
%
%  Queue Event for the app Port belongs to, from any thread. Does nothing
%  if the app has ended.
port_send(port(Wake), Event) :-
    catch(wake_post(Wake, Event),
          error(existence_error(_, _), _),
          true).


'#subscriptions'.

%!  subscriptions_open(+Port, -Subscriptions) is det.
%
%  Subscriptions holds the running subscriptions of the app Port belongs
%  to, none yet: Sub-Thread pairs, kept in a mutable term so that they
%  can be stopped however the app ends.
subscriptions_open(Port, subscriptions(Port, [])).

%!  subscriptions_running(+Subscriptions, +Module, +Subs) is det.
%
%  IMPURE: makes the running subscriptions Subs: stops those not in Subs
%  and starts those new in it, thread goals in Module.
subscriptions_running(Subscriptions, M, Subs) :-
    must_be(list, Subs),
    maplist(must_be_subscription, Subs),
    Subscriptions = subscriptions(Port, Running0),
    running_subs_stopped_started(Running0, Subs, Stopped, Started),
    maplist(subscription_stopped, Stopped),
    maplist(port_module_subscription_started(Port, M), Started, New),
    exclude(running_in(Stopped), Running0, Kept),
    append(Kept, New, Running),
    nb_setarg(2, Subscriptions, Running).    % IMPURE: see subscriptions_open/2

running_in(Stopped, Running) :-
    member(S, Stopped),
    S == Running, !.

%!  subscriptions_closed(+Subscriptions) is det.
%
%  IMPURE: stops every running subscription.
subscriptions_closed(Subscriptions) :-
    Subscriptions = subscriptions(_, Running),
    maplist(subscription_stopped, Running),
    nb_setarg(2, Subscriptions, []).

%!  running_subs_stopped_started(+Running, +Subs, -Stopped, -Started) is det.
%
%  Running is a list of Sub-Thread pairs and Subs the subscriptions
%  wanted. Stopped are the pairs whose Sub is not wanted, Started the
%  wanted Subs not running. Subs are compared as variants.
running_subs_stopped_started(Running, Subs, Stopped, Started) :-
    exclude(pair_wanted(Subs), Running, Stopped),
    exclude(sub_running(Running), Subs, Started0),
    list_variants_deduped(Started0, Started).

pair_wanted(Subs, Sub-_) :-
    member(S, Subs),
    S =@= Sub, !.

sub_running(Running, Sub) :-
    member(S-_, Running),
    S =@= Sub, !.

list_variants_deduped([], []).
list_variants_deduped([X | Xs], [X | Ys]) :-
    exclude(=@=(X), Xs, Xs1),
    list_variants_deduped(Xs1, Ys).

must_be_subscription(every(Ms, _)) :-
    number(Ms),
    Ms > 0, !.
must_be_subscription(thread(Goal)) :-
    callable(Goal), !.
must_be_subscription(Sub) :-
    domain_error(tui_subscription, Sub).


'#threads'.

% IMPURE: starts Sub in a detached thread.
port_module_subscription_started(Port, M, Sub, Sub-Thread) :-
    thread_create(subscription_run(Sub, M, Port), Thread, [detached(true)]).

% IMPURE: asks the thread to stop, if it is still running.
subscription_stopped(_-Thread) :-
    catch(thread_signal(Thread, throw(tui_stop)),
          error(existence_error(_, _), _),
          true).

% Runs in the subscription's thread.
subscription_run(every(Ms, Event), _, Port) :-
    catch(( get_time(T0),
            every_from_sent(Ms, Event, T0, Port) ),
          tui_stop,
          true).
subscription_run(thread(Goal), M, Port) :-
    catch(( catch(( call(M:Goal, Port)
                  ->  Status = true
                  ;   Status = false
                  ),
                  E,
                  (   E == tui_stop
                  ->  throw(tui_stop)
                  ;   Status = exception(E)
                  )),
            port_send(Port, thread_ended(Goal, Status)) ),
          tui_stop,
          true).

% IMPURE: sends Event at T + Ms, T + 2Ms, ...; the deadlines do not
% drift with the time sending takes.
every_from_sent(Ms, Event, T, Port) :-
    Next is T + Ms / 1000,
    get_time(Now),
    Delay is Next - Now,
    (   Delay > 0
    ->  sleep(Delay)
    ;   true
    ),
    port_send(Port, Event),
    every_from_sent(Ms, Event, Next, Port).
