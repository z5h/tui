:- module(tui_substrate,
          [
            substrate_session/3,
            substrate_events/4,
            substrate_cleared/2,
            substrate_runs_painted/3
          ]).

/** <module> Substrates

What the event loop draws onto and receives events from. A substrate is
a term: `terminal` for a real ANSI terminal, or vcr(Script) to replay a
script (see tui/vcr.pl). Operations take a substrate and give back the
substrate as it is afterwards.

Events are already decoded: keys (up, ' ', ...) and terminal_size(Cols,
Rows), which arrives at the start of a session and after every resize.
*/

:- use_module(library(tui/utils)).
:- use_module(library(tui/terminal)).
:- use_module(library(tui/wake)).
:- use_module(library(tui/vcr)).


'#session'.

%  substrate_session(+Substrate, +Wake, :Goal)
%
%  Run Goal with Substrate set up for an app, restoring it afterwards.
%  Posted events reach the app through Wake.
:- meta_predicate(substrate_session(+, +, 0)).
substrate_session(terminal, Wake, Goal) :-
    with_tty_raw(
        setup_call_cleanup(
            (   asserta(winch_wake_(Wake)),
                on_signal(winch, Old, sig_winch),
                ansi_reset,
                ansi_hide_cursor,
                tty_request_size
            ),
            Goal,
            (   @ on_signal(winch, _, Old),
                @ retract(winch_wake_(Wake)),
                @ ansi_reset,
                @ ansi_show_cursor
            )
        )
    ).
substrate_session(vcr(_), _, Goal) :-
    call(Goal).

% IMPURE: mutable global — where a SIGWINCH is delivered. A signal
% handler receives only the signal, so there is no other way to reach it.
:- dynamic winch_wake_/1.

% Runs in the main thread, possibly mid-render, so it must not write to
% the terminal. substrate_events/4 issues the size request instead.
sig_winch(_) :-
    winch_wake_(Wake), !,
    wake_post(Wake, terminal_resized).


'#events'.

% IMPURE: blocks until input or a wake, then returns everything ready.
% A terminal_resized wake is answered with a size request; the reply
% arrives later as terminal_size(Cols, Rows).
substrate_events(terminal, Wake, Events, terminal) :-
    wake_stream(Wake, WakeIn),
    wait_for_input([user_input, WakeIn], Ready, infinite),
    (   memberchk(WakeIn, Ready)
    ->  wake_events(Wake, Posted0)
    ;   Posted0 = []
    ),
    (   memberchk(terminal_resized, Posted0)
    ->  tty_request_size
    ;   true
    ),
    exclude(==(terminal_resized), Posted0, Posted),
    (   memberchk(user_input, Ready)
    ->  tty_events(Inputs)
    ;   Inputs = []
    ),
    append(Posted, Inputs, Events).
substrate_events(vcr(Script0), _, Events, vcr(Script)) :-
    vcr_events(Script0, Events, Script).

% IMPURE: one input, plus any others available without blocking.
tty_events([In | Ins]) :-
    get_single_input(In),
    (   wait_for_input([user_input], [_], 0)
    ->  tty_events(Ins)
    ;   Ins = []
    ).


'#painting'.

% IMPURE: nothing is on the substrate afterwards.
substrate_cleared(terminal, terminal) :-
    ansi_reset.
substrate_cleared(vcr(Script0), vcr(Script)) :-
    vcr_cleared(Script0, Script).

% IMPURE: draws Runs, (X-Y)-(Attrs-Chars), over what is there.
substrate_runs_painted(terminal, Runs, terminal) :-
    ansi_hide_cursor,
    maplist(ansi_run, Runs),
    flush_output.
substrate_runs_painted(vcr(Script0), Runs, vcr(Script)) :-
    vcr_runs_painted(Script0, Runs, Script).
