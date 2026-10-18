:- module(tui_substrate,
          [
            terminal_substrate/1,
            substrate_session/3,
            substrate_events/4,
            substrate_cleared/2,
            substrate_runs_painted/3,
            substrate_graphics_sent/3
          ]).

/** <module> Substrates

What the event loop draws onto and receives events from. A substrate is
a term: terminal(Keyboard, Pending) for a real ANSI terminal (start from
terminal_substrate/1), or vcr(Script) to replay a script (see
tui/vcr.pl). Operations take a substrate and give back the substrate as
it is afterwards.

Events are already decoded (see tui/input.pl): keys,
terminal_size(Cols, Rows), which arrives at the start of a session and
after every resize, and terminal_properties(Properties), which arrives
once, shortly after the start. Properties holds program(Program),
extended_keys(Bool) and graphics(Bool), in no guaranteed order.
*/

:- use_module(library(tui/utils)).
:- use_module(library(tui/terminal)).
:- use_module(library(tui/input)).
:- use_module(library(tui/wake)).
:- use_module(library(tui/vcr)).

% How long a pending escape sequence may wait for the rest of its codes.
escape_grace(0.01).


'#session'.

% A terminal before its session. Detected is Keyboard-Graphics: Keyboard
% is detecting until the terminal reveals whether it supports the Kitty
% keyboard protocol (then kitty) or not (then legacy); Graphics becomes
% true if it answers the Kitty graphics query. Pending holds codes of an
% incomplete escape sequence.
terminal_substrate(terminal(detecting-false, [])).

%  substrate_session(+Substrate, +Wake, :Goal)
%
%  Run Goal with Substrate set up for an app, restoring it afterwards.
%  Posted events reach the app through Wake.
:- meta_predicate(substrate_session(+, +, 0)).
substrate_session(terminal(_, _), Wake, Goal) :-
    with_tty_raw(
        setup_call_cleanup(
            (   asserta(winch_wake_(Wake)),
                on_signal(winch, Old, sig_winch),
                ansi_reset,
                ansi_hide_cursor,
                ansi_bracketed_paste_on,
                ansi_kitty_keyboard_query,
                ansi_kitty_graphics_query,
                ansi_primary_device_attributes,
                flush_output,
                size_posted(Wake)
            ),
            Goal,
            (   @ on_signal(winch, _, Old),
                @ retract(winch_wake_(Wake)),
                @ ansi_kitty_keyboard_pop,
                @ ansi_bracketed_paste_off,
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
% the terminal.
sig_winch(_) :-
    winch_wake_(Wake), !,
    size_posted(Wake).

% IMPURE: posts the terminal's size, from the OS.
size_posted(Wake) :-
    tty_size(Rows, Cols),
    wake_post(Wake, terminal_size(Cols, Rows)).


'#events'.

% IMPURE: blocks until input or a wake, then returns everything ready.
% While an escape sequence is pending, waits at most the escape grace
% period; if nothing arrives, the pending codes are decoded as they are.
% An open paste waits for its end however long that takes. End of input
% is the event eos.
substrate_events(terminal(K0, Pending0), Wake, Events, terminal(K, Pending)) :-
    wake_stream(Wake, WakeIn),
    (   (   Pending0 == []
        ;   pending_paste_open(Pending0)
        )
    ->  Timeout = infinite
    ;   escape_grace(Timeout)
    ),
    wait_for_input([user_input, WakeIn], Ready, Timeout),
    (   memberchk(WakeIn, Ready)
    ->  wake_events(Wake, Posted)
    ;   Posted = []
    ),
    (   Ready == []
    ->  pending_events_flushed(Pending0, Decoded),
        Pending = []
    ;   memberchk(user_input, Ready)
    ->  user_input_codes(Codes),
        (   Codes == []
        ->  Decoded = [eos],
            Pending = []
        ;   append(Pending0, Codes, Codes1),
            codes_events_pending(Codes1, Decoded, Pending)
        )
    ;   Decoded = [],
        Pending = Pending0
    ),
    keyboard_events_keys(K0, Decoded, K, Keys),
    append(Posted, Keys, Events).
substrate_events(vcr(Script0), _, Events, vcr(Script)) :-
    vcr_events(Script0, Events, Script).

% IMPURE: the codes available on user_input; [] at end of input.
user_input_codes(Codes) :-
    fill_buffer(user_input),
    read_pending_codes(user_input, Codes, []).

% IMPURE: terminal replies drive detection and are not passed on. A
% Kitty keyboard reply before the device attributes reply means the
% protocol is supported, and it is enabled; an OK graphics reply means
% images can be shown. The device attributes reply, requested once at
% session start, ends detection: it becomes
% terminal_properties(Properties).
keyboard_events_keys(K, [], K, []).
keyboard_events_keys(Kb0-G0, [E | Es], K, Keys) :-
    (   E = kitty_keyboard(_)
    ->  (   Kb0 == detecting
        ->  ansi_kitty_keyboard_push(1),
            flush_output,
            Kb1 = kitty
        ;   Kb1 = Kb0
        ),
        G1 = G0,
        Keys = Keys1
    ;   E = kitty_graphics(Reply)
    ->  (   string_concat(_, ";OK", Reply)
        ->  G1 = true
        ;   G1 = G0
        ),
        Kb1 = Kb0,
        Keys = Keys1
    ;   E = device_attributes(_)
    ->  (   Kb0 == detecting
        ->  Kb1 = legacy
        ;   Kb1 = Kb0
        ),
        G1 = G0,
        detected_properties(Kb1-G1, Properties),
        Keys = [terminal_properties(Properties) | Keys1]
    ;   Kb1 = Kb0,
        G1 = G0,
        Keys = [E | Keys1]
    ),
    keyboard_events_keys(Kb1-G1, Es, K, Keys1).

% IMPURE: reads the environment. program(P) is TERM_PROGRAM, as set by
% the terminal (e.g. 'Apple_Terminal'), or unknown; extended_keys(B) is
% whether modified keys are unambiguous (the Kitty keyboard protocol);
% graphics(G) is whether images can be shown (the Kitty graphics
% protocol).
detected_properties(Kb-G, [program(P), extended_keys(B), graphics(G)]) :-
    (   getenv('TERM_PROGRAM', P0)
    ->  atom_string(P, P0)
    ;   P = unknown
    ),
    (   Kb == kitty
    ->  B = true
    ;   B = false
    ).


'#painting'.

% IMPURE: nothing is on the substrate afterwards.
substrate_cleared(terminal(K, P), terminal(K, P)) :-
    ansi_clear.
substrate_cleared(vcr(Script0), vcr(Script)) :-
    vcr_cleared(Script0, Script).

% IMPURE: draws Runs, (X-Y)-(Attrs-Chars), over what is there.
substrate_runs_painted(terminal(K, P), Runs, terminal(K, P)) :-
    ansi_hide_cursor,
    maplist(ansi_run, Runs),
    flush_output.
substrate_runs_painted(vcr(Script0), Runs, vcr(Script)) :-
    vcr_runs_painted(Script0, Runs, Script).

% IMPURE: sends image Actions, transmit(Id, Source) and place(Id, W-H)
% (see tui/image.pl).
substrate_graphics_sent(terminal(K, P), Actions, terminal(K, P)) :-
    maplist(graphics_action_sent, Actions),
    flush_output.
substrate_graphics_sent(vcr(Script0), Actions, vcr(Script)) :-
    vcr_graphics_sent(Script0, Actions, Script).

graphics_action_sent(transmit(Id, Source)) :-
    ansi_kitty_image_transmit(Id, Source).
graphics_action_sent(place(Id, WH)) :-
    ansi_kitty_image_place(Id, WH).
