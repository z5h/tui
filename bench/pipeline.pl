:- module(bench_pipeline, []).

/** <module> Rendering pipeline benchmark

How long tui's rendering logic takes to turn a view into runs, stage by
stage, before anything reaches a terminal. Runs anywhere:

    swipl -p library=prolog bench/pipeline.pl [REPEATS]

Each stage runs REPEATS times (default 10); the median is reported, in
milliseconds. Stages, in the order the loop runs them:

  * view    — calling the app's view
  * expand  — expanding drawables into commands
  * dedupe  — removing overdrawn cells
  * map     — the event map (on-screen cells and their stacks)
  * assoc   — indexing the event map
  * cursor  — finding a cursor(_) cell, and hover focus
  * images  — finding the image/3 terms on screen
  * runs    — resolving cells and grouping them into runs
  * diff    — runs that changed (against an identical frame)
*/

:- use_module(library(tui)).
:- use_module(library(tui/utils)).
:- use_module(library(tui/drawable)).
:- use_module(library(tui/hover)).
:- use_module(library(tui/events)).
:- use_module(library(tui/render)).
:- use_module(library(tui/loop)).

:- use_module('../examples/gallery', []).
:- use_module('../examples/atto', []).

:- initialization(main, main).

main :-
    current_prolog_flag(argv, Argv),
    (   Argv = [A]
    ->  atom_number(A, Repeats)
    ;   Repeats = 10
    ),
    format("Pipeline benchmark: median of ~d, in ms~n~n", [Repeats]),
    format("~w~t~14|~w~t~8+~w~t~7+~w~t~8+~w~t~8+~w~t~8+~w~t~8+~w~t~8+~w~t~8+~w~t~8+~w~t~8+~w~t~8+~w~t~9+~n",
           [scene, cells, runs, view, expand, dedupe, map, assoc, cursor, images, runs, diff, total]),
    forall(scene(Name, Size, State, View),
           scene_reported(Name, Size, State, View, Repeats)).


'#scenes'.

% scene(Name, Cols-Rows, State, View)
scene(text, 120-40, (1-1)-none, text_view).
scene(styled, 120-40, (1-1)-none, styled_view).
scene(gallery, 80-25, State, gallery:view) :-
    gallery:state0(State).
scene(atto_100, 120-40, _-M, atto:state_view) :-
    atto_model(100, 120-40, M).
scene(atto_2000, 120-40, _-M, atto:state_view) :-
    atto_model(2000, 120-40, M).

% A full screen of text: one string per row.
text_view(_, column(Lines)) :-
    findall(S,
            ( between(1, 40, Y),
              Code is 0'a + Y mod 26,
              length(Codes, 120),
              maplist(=(Code), Codes),
              string_codes(S, Codes)
            ),
            Lines).

% A full screen of cells, each styled differently from its neighbours.
styled_view(_, Cells) :-
    Colors = [red, green, yellow, blue, magenta, cyan],
    findall(X-Y-style([fg(Color)], Ch),
            ( between(0, 39, Y),
              between(0, 119, X),
              I is (X + Y) mod 6,
              nth0(I, Colors, Color),
              Code is 0'a + I,
              char_code(Ch, Code)
            ),
            Cells).

% An atto model of N generated lines of varying length, some wrapping.
atto_model(N, Size, atto('bench.txt', Lines, 0-0, 0, false, none, Size)) :-
    Words = [lorem, ipsum, dolor, sit, amet, consectetur, adipiscing, elit],
    findall(Chars,
            ( between(1, N, I),
              Count is I mod 40,
              findall(W, ( between(1, Count, J), K is (I + J) mod 8, nth0(K, Words, W) ), Ws),
              atomic_list_concat(Ws, ' ', A),
              atom_chars(A, Chars)
            ),
            Lines).


'#stages'.

scene_reported(Name, Size, State, View, Repeats) :-
    stage_ms(Repeats, call(View, State, D), TView),
    % As the loop draws it: in a zone the size of the substrate.
    stage_ms(Repeats, phrase(drawable(zone(Size, D), [], [], 1-1, _), Cmds0), TExpand),
    stage_ms(Repeats, keylist_deduped_prioritize_last(Cmds0, Cmds), TDedupe),
    stage_ms(Repeats, limits_commands_eventmap(Size, Cmds, EventMap), TMap),
    stage_ms(Repeats, list_to_assoc(EventMap, _), TAssoc),
    stage_ms(Repeats, cursor_focused(State, EventMap, Cmds, Cursor), TCursor),
    stage_ms(Repeats, tui_loop:limits_commands_images(Size, Cmds, _), TImages),
    stage_ms(Repeats, limits_cursor_commands_runs(Size, Cursor, Cmds, Runs), TRuns),
    stage_ms(Repeats, runs_previous_changed(Runs, Runs, _), TDiff),
    length(Cmds, Cells),
    length(Runs, RunCount),
    Total is TView + TExpand + TDedupe + TMap + TAssoc + TCursor + TImages + TRuns + TDiff,
    format("~w~t~14|~d~t~8+~d~t~7+~2f~t~8+~2f~t~8+~2f~t~8+~2f~t~8+~2f~t~8+~2f~t~8+~2f~t~8+~2f~t~8+~2f~t~8+~2f~t~9+~n",
           [Name, Cells, RunCount, TView, TExpand, TDedupe, TMap, TAssoc, TCursor, TImages, TRuns, TDiff, Total]).

cursor_focused(State, EventMap, Cmds, Cursor) :-
    tui_loop:state_eventmap_cursor(State, EventMap, Cursor),
    (   Cursor = X-Y
    ->  once(apply_focus(X-Y, Cmds))
    ;   true
    ).

% The median time of Goal over Repeats runs, in ms. Goal's bindings are
% kept from one final, untimed run.
:- meta_predicate stage_ms(+, 0, -).
stage_ms(Repeats, Goal, Ms) :-
    findall(T,
            ( between(1, Repeats, _),
              garbage_collect,
              \+ \+ ( get_time(T0),
                      once(Goal),
                      get_time(T1),
                      nb_setval(bench_ms, T1-T0)
                    ),
              nb_getval(bench_ms, E-S),
              T is (E - S) * 1000
            ),
            Ts),
    msort(Ts, Sorted),
    length(Sorted, L),
    I is L // 2,
    nth0(I, Sorted, Ms),
    once(Goal).
