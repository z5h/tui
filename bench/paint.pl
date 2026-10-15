:- module(bench_paint, []).

/** <module> Painting benchmark

How long a terminal takes to draw what tui sends it. Run it in the
terminal (or tmux, screen, ...) to measure:

    swipl -p library=prolog bench/paint.pl [FRAMES]

Each scenario paints prepared runs through the terminal substrate, so
none of tui's rendering logic is measured. A write returns once the OS
has the bytes, not once the terminal has drawn them, so after painting
the benchmark requests the terminal's device attributes and waits for
the reply, which comes only after everything before it is processed.

  * stream: FRAMES frames back to back, then one sync. Throughput.
  * synced: a sync after every frame. Latency, mean and worst.
*/

:- use_module(library(tui/terminal)).
:- use_module(library(tui/input)).
:- use_module(library(tui/substrate)).

:- initialization(main, main).

main :-
    current_prolog_flag(argv, Argv),
    (   Argv = [A]
    ->  atom_number(A, Frames)
    ;   Frames = 100
    ),
    tty_size(Rows, Cols),
    with_tty_raw(
        setup_call_cleanup(
            (   ansi_reset,
                ansi_hide_cursor,
                flush_output
            ),
            findall(R,
                    ( scenario(Name),
                      scenario_size_frames_result(Name, Cols-Rows, Frames, R)
                    ),
                    Results),
            (   ansi_reset,
                ansi_show_cursor,
                flush_output
            )
        )
    ),
    report(Cols-Rows, Frames, Results).


'#scenarios'.

scenario(full_plain).
scenario(full_styled).
scenario(row).
scenario(cell).

% Two alternating frames, so every frame differs from the one before.
scenario_size_frame_runs(full_plain, Cols-Rows, K, Runs) :-
    findall((1-Y)-([]-Chars),
            ( between(1, Rows, Y),
              Code is 0'a + (Y + K) mod 26,
              char_code(Ch, Code),
              length(Chars, Cols),
              maplist(=(Ch), Chars)
            ),
            Runs).
scenario_size_frame_runs(full_styled, Cols-Rows, K, Runs) :-
    Colors = [red, green, yellow, blue, magenta, cyan],
    findall((X-Y)-([fg(Color)]-[Ch]),
            ( between(1, Rows, Y),
              between(1, Cols, X),
              I is (X + Y + K) mod 6,
              nth0(I, Colors, Color),
              Code is 0'a + I,
              char_code(Ch, Code)
            ),
            Runs).
scenario_size_frame_runs(row, Cols-Rows, K, [(1-Y)-([]-Chars)]) :-
    Y is max(1, Rows // 2),
    Code is 0'a + K,
    char_code(Ch, Code),
    length(Chars, Cols),
    maplist(=(Ch), Chars).
scenario_size_frame_runs(cell, Cols-Rows, K, [(X-Y)-(Attrs-[x])]) :-
    X is max(1, Cols // 2),
    Y is max(1, Rows // 2),
    (   K =:= 0
    ->  Attrs = [negative]
    ;   Attrs = []
    ).


'#measuring'.

scenario_size_frames_result(Name, Size, Frames,
                            result(Name, RunCount, CellCount, StreamMs, SyncedMs, WorstMs)) :-
    scenario_size_frame_runs(Name, Size, 0, Runs0),
    scenario_size_frame_runs(Name, Size, 1, Runs1),
    length(Runs0, RunCount),
    foldl(run_cells_added, Runs0, 0, CellCount),
    ansi_clear,
    synced,
    get_time(T0),
    forall(between(1, Frames, I), frame_painted(I, Runs0, Runs1)),
    synced,
    get_time(T1),
    StreamMs is (T1 - T0) * 1000 / Frames,
    findall(Ms,
            ( between(1, Frames, I),
              get_time(S0),
              frame_painted(I, Runs0, Runs1),
              synced,
              get_time(S1),
              Ms is (S1 - S0) * 1000
            ),
            Times),
    sum_list(Times, Total),
    SyncedMs is Total / Frames,
    max_list(Times, WorstMs).

run_cells_added(_-(_-Chars), N0, N) :-
    length(Chars, L),
    N is N0 + L.

% IMPURE: paints frame I through the terminal substrate.
frame_painted(I, Runs0, Runs1) :-
    (   I mod 2 =:= 0
    ->  Runs = Runs0
    ;   Runs = Runs1
    ),
    substrate_runs_painted(terminal(legacy, []), Runs, _).

% IMPURE: returns once the terminal has processed all output so far.
synced :-
    ansi_primary_device_attributes,
    flush_output,
    reply_awaited([]).

reply_awaited(Pending0) :-
    (   wait_for_input([user_input], [_], 5)
    ->  fill_buffer(user_input),
        read_pending_codes(user_input, Codes, []),
        append(Pending0, Codes, All),
        codes_events_pending(All, Events, Pending),
        (   memberchk(device_attributes(_), Events)
        ->  true
        ;   reply_awaited(Pending)
        )
    ;   throw(error(no_terminal_reply, _))
    ).


'#report'.

report(Cols-Rows, Frames, Results) :-
    format("Painting benchmark: ~dx~d, ~d frames per scenario~n", [Cols, Rows, Frames]),
    forall(member(Var, ['TERM', 'TERM_PROGRAM', 'TMUX', 'STY']),
           (   getenv(Var, Value)
           ->  format("  ~w=~w~n", [Var, Value])
           ;   true
           )),
    format("~n~w~t~14|~w~t~8+~w~t~9+~w~t~14+~w~t~14+~w~t~12+~n",
           [scenario, runs, cells, 'stream ms', 'synced ms', 'worst ms']),
    forall(member(result(Name, Runs, Cells, Stream, Synced, Worst), Results),
           format("~w~t~14|~d~t~8+~d~t~9+~3f~t~14+~3f~t~14+~3f~t~12+~n",
                  [Name, Runs, Cells, Stream, Synced, Worst])).
