:- module(test_tui, []).

:- use_module(library(plunit)).
:- use_module(library(tui)).
:- use_module(library(tui/assocs)).
:- use_module(library(tui/utils)).

:- op(601, xfy, '.>').
:- op(601, xfy, '.\\/').


:- begin_tests(assocs).

test(empty) :-
    empty_assocs(A),
    A == [].

test(pair_found, [nondet]) :-
    assocs_pair([a-1, b-2], a-1).

test(pair_second, [nondet]) :-
    assocs_pair([a-1, b-2], b-2).

test(pair_not_found, [fail]) :-
    assocs_pair([a-1, b-2], c-_).

test(pairs_all, [nondet]) :-
    assocs_pairs([a-1, b-2, c-3], [c-3, a-1]).

test(pairs_partial_match, [nondet]) :-
    assocs_pairs([a-1, b-2], [a-V]),
    V == 1.

test(pairs_empty) :-
    assocs_pairs([a-1], []).

test(pair_assocs_add, [nondet]) :-
    assocs_pair_assocs([a-1], b-2, R),
    R == [b-2, a-1].

test(pair_pair_update, [nondet]) :-
    pair_pair_assocs_assocs(a-_, a-99, [a-1, b-2], R),
    assocs_pairs(R, [a-99, b-2]).

test(pair_pair_change_key, [nondet]) :-
    pair_pair_assocs_assocs(a-_, x-99, [a-1, b-2], R),
    assocs_pairs(R, [x-99, b-2]).

:- end_tests(assocs).


:- begin_tests(utils).

test(mapindexed_basic) :-
    mapindexed([I, X, I-X]>>true, [a, b, c], R),
    R == [1-a, 2-b, 3-c].

test(mapindexed_empty) :-
    mapindexed([_, _, _]>>true, [], R),
    R == [].

:- end_tests(utils).


:- begin_tests(drawables).

test(atom_renders) :-
    drawable_raw(hi, raw(Cmds)),
    length(Cmds, 2).

test(string_renders) :-
    drawable_raw("abc", raw(Cmds)),
    length(Cmds, 3).

test(hconcat_width) :-
    drawable_raw("ab" .> "cd", raw(Cmds)),
    length(Cmds, 4).

test(vconcat) :-
    drawable_raw("a" .\/ "b", raw(Cmds)),
    length(Cmds, 2),
    Cmds = [(0-0)-(_-_-a), (0-1)-(_-_-b)].

test(translate) :-
    drawable_raw(translate(5-3, "x"), raw([(X-Y)-(_-_-x)])),
    X == 5,
    Y == 3.

test(translate_shorthand) :-
    drawable_raw(5-3-"x", raw([(X-Y)-(_-_-x)])),
    X == 5,
    Y == 3.

test(style_preserves_content) :-
    drawable_raw(style([bold], "x"), raw([(0-0)-(_-[[bold]]-x)])).

test(list_overlay) :-
    drawable_raw(["a", "b"], raw(Cmds)),
    length(Cmds, 2).

test(empty_list) :-
    drawable_raw([], raw(Cmds)),
    Cmds == [].

test(literal_number) :-
    drawable_raw(literal(42), raw(Cmds)),
    length(Cmds, 2).

test(column_component) :-
    drawable_raw(column(["a", "b", "c"]), raw(Cmds)),
    length(Cmds, 3).

test(row_component) :-
    drawable_raw(row(["a", "b"]), raw(Cmds)),
    length(Cmds, 2).

test(box_corners) :-
    drawable_raw(box(3-3, thin), raw(Cmds)),
    length(Cmds, L),
    L > 0.

test(clear_fills) :-
    drawable_raw(clear(2-2), raw(Cmds)),
    length(Cmds, 9).  % 0..2 x 0..2 = 3x3

:- end_tests(drawables).
