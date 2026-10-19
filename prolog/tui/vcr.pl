:- module(tui_vcr,
          [
            vcr_events/3,
            vcr_cleared/2,
            vcr_runs_painted/3,
            vcr_graphics_sent/3
          ]).

/** <module> VCR

Replays a script of what an app is expected to send to its substrate
and what the substrate sends back. A script is a list of:

  * send(Events)      — the next batch of events the app receives
  * receive(N)        — the next batch is the next N events sent to the
    app's port, by its subscriptions; waits for them (at most 5 s each)
  * expect(clear)     — the app clears the substrate
  * expect(runs(Runs)) — the app paints exactly Runs, (X-Y)-(Attrs-Chars);
    if Runs is unbound, any paint (it stays unbound)
  * expect(graphics(Actions)) — the app sends exactly these image actions
    (see tui/image.pl), before the runs of the same paint

Entries are consumed in order. Anything the app does that does not match
the next entry throws error(vcr_mismatch(Expected, Actual), _), where
Actual is written as the entry that would have matched. Once the script
is empty, every request for events receives [eos].

A typical script starts with the substrate reporting its size:

    [ send([terminal_size(80, 25)]),
      expect(clear),
      expect(runs(...)),
      ...
    ]
*/


'#replay'.

%!  vcr_events(+Script0, -Batch, -Script) is det.
%
%  Batch is the next batch of events, or received(N) for the next N
%  events posted to the app (by its subscriptions), which the substrate
%  waits for. Script is what remains. An empty script gives [eos].
%
%  @error vcr_mismatch(Expected, send(_)) if the script expects
%  something else next.
vcr_events([], [eos], []) :- !.
vcr_events([send(Events) | Script], Events, Script) :- !.
vcr_events([receive(N) | Script], received(N), Script) :- !.
vcr_events(Script, _, _) :-
    script_mismatch(Script, send(_)).

%!  vcr_cleared(+Script0, -Script) is det.
%
%  The app cleared the substrate, as Script0 expects next.
%
%  @error vcr_mismatch(Expected, expect(clear)) otherwise.
vcr_cleared([expect(clear) | Script], Script) :- !.
vcr_cleared(Script, _) :-
    script_mismatch(Script, expect(clear)).

%!  vcr_runs_painted(+Script0, +Runs, -Script) is det.
%
%  The app painted Runs, as Script0 expects next (an unbound expectation
%  matches any runs). Painting nothing is not something the app sends,
%  so it consumes nothing.
%
%  @error vcr_mismatch(Expected, expect(runs(Runs))) otherwise.
vcr_runs_painted(Script, [], Script) :- !.
vcr_runs_painted([expect(runs(Expected)) | Script], Runs, Script) :-
    (   var(Expected)
    ;   Expected == Runs
    ), !.
vcr_runs_painted(Script, Runs, _) :-
    script_mismatch(Script, expect(runs(Runs))).

%!  vcr_graphics_sent(+Script0, +Actions, -Script) is det.
%
%  The app sent the image Actions, as Script0 expects next. Sending none
%  consumes nothing.
%
%  @error vcr_mismatch(Expected, expect(graphics(Actions))) otherwise.
vcr_graphics_sent(Script, [], Script) :- !.
vcr_graphics_sent([expect(graphics(Expected)) | Script], Actions, Script) :-
    Expected == Actions, !.
vcr_graphics_sent(Script, Actions, _) :-
    script_mismatch(Script, expect(graphics(Actions))).

script_mismatch([], Actual) :-
    throw(error(vcr_mismatch(end_of_script, Actual), _)).
script_mismatch([Expected | _], Actual) :-
    throw(error(vcr_mismatch(Expected, Actual), _)).


'#messages'.

:- multifile prolog:error_message//1.

prolog:error_message(vcr_mismatch(Expected, Actual)) -->
    [ 'VCR script mismatch:', nl,
      '  expected: ~q'-[Expected], nl,
      '  actual:   ~q'-[Actual] ].
