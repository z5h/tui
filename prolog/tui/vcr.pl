:- module(tui_vcr,
          [
            vcr_events/3,
            vcr_cleared/2,
            vcr_runs_painted/3
          ]).

/** <module> VCR

Replays a script of what an app is expected to send to its substrate
and what the substrate sends back. A script is a list of:

  * send(Events)      — the next batch of events the app receives
  * expect(clear)     — the app clears the substrate
  * expect(runs(Runs)) — the app paints exactly Runs, (X-Y)-(Attrs-Chars)

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

vcr_events([], [eos], []) :- !.
vcr_events([send(Events) | Script], Events, Script) :- !.
vcr_events(Script, _, _) :-
    script_mismatch(Script, send(_)).

vcr_cleared([expect(clear) | Script], Script) :- !.
vcr_cleared(Script, _) :-
    script_mismatch(Script, expect(clear)).

% Painting nothing is not something the app sends.
vcr_runs_painted(Script, [], Script) :- !.
vcr_runs_painted([expect(runs(Expected)) | Script], Runs, Script) :-
    Expected == Runs, !.
vcr_runs_painted(Script, Runs, _) :-
    script_mismatch(Script, expect(runs(Runs))).

script_mismatch([], Actual) :-
    throw(error(vcr_mismatch(end_of_script, Actual), _)).
script_mismatch([Expected | _], Actual) :-
    throw(error(vcr_mismatch(Expected, Actual), _)).
