:- module(test_tui, []).

:- use_module(library(plunit)).
:- use_module(library(tui)).
:- use_module(library(tui/assocs)).
:- use_module(library(tui/utils)).
:- use_module(library(tui/loop), [app/5]).
:- use_module(library(tui/input)).

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


:- begin_tests(hover).

cursor_drawable_runs(Cursor, D, Runs) :-
    tui_drawable:drawable__normalized_commands__end(D, Cmds, _),
    once(tui_hover:apply_focus(Cursor, Cmds)),
    tui_render:limits_cursor_commands_runs(80-25, Cursor, Cmds, Runs).

test(hovered) :-
    cursor_drawable_runs(1-1, hover([bold], "ab") .> "cd", Runs),
    Runs == [(1-1)-([bold, negative]-[a]),
             (2-1)-([bold]-[b]),
             (3-1)-([]-[c, d])].

test(not_hovered) :-
    cursor_drawable_runs(3-1, hover([bold], "ab") .> "cd", Runs),
    Runs == [(1-1)-([]-[a, b]),
             (3-1)-([negative]-[c]),
             (4-1)-([]-[d])].

:- end_tests(hover).


:- begin_tests(vcr).

% Shows "hi"; records each event it receives; quits on eos.
vcr_view(_, "hi").

vcr_update(eos, S, result(S)) :- !.
vcr_update(E, (X-Y)-Es, (X-Y)-[E | Es]).

test(replay) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(1-1)-([negative]-[h]), (2-1)-([]-[i])])),
               send([a]),
               send([right]),
               expect(runs([(1-1)-([]-[h]), (2-1)-([negative]-[i])]))
             ],
    app(vcr(Script), (1-1)-[], vcr_view, vcr_update, Result),
    Result == (2-1)-[a].

test(mismatch, [throws(error(vcr_mismatch(expect(runs(_)), expect(clear)), _))]) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(runs([]))
             ],
    app(vcr(Script), (1-1)-[], vcr_view, vcr_update, _).

:- end_tests(vcr).


:- begin_tests(input).

% Codes - Events, decoding completely.
decoded(`a`,                [a]).
decoded(`A`,                ['A']).
decoded([1],                [ctrl+a]).
decoded([0],                [ctrl+' ']).
decoded([9],                [tab]).
decoded([13],               [return]).
decoded([127],              [backspace]).
decoded(`\e[A`,             [up]).
decoded(`\eOA`,             [up]).
decoded(`\eOP`,             [f1]).
decoded(`\e[13~`,           [f3]).
decoded(`\e[24~`,           [f12]).
decoded(`\e[3~`,            [delete]).
decoded(`\e[1;5A`,          [ctrl+up]).
decoded(`\e[1;8D`,          [ctrl+alt+shift+left]).
decoded(`\e[5;2~`,          [shift+page_up]).
decoded(`\e[1;5P`,          [ctrl+f1]).
decoded(`\e[Z`,             [shift+tab]).
decoded(`\ex`,              [alt+x]).
decoded(`\eA`,              [alt+shift+a]).
decoded([27, 1],            [ctrl+alt+a]).
decoded(`\e\e[A`,           [escape, up]).
decoded(`\e[27;5;105~`,     [ctrl+i]).
decoded(`\e[105;5u`,        [ctrl+i]).
decoded(`\e[97;6u`,         [ctrl+shift+a]).
decoded(`\e[27u`,           [escape]).
decoded(`\e[13;3u`,         [alt+return]).
decoded(`\e[57376u`,        [f13]).
decoded(`\e[1;10A`,         [shift+super+up]).
decoded(`\e[?1u\e[?62;22c`, [kitty_keyboard(1), device_attributes([62, 22])]).
decoded(`\e[3~x`,           [delete, x]).
decoded(`\e[1;5X`,          [unknown_input(`\e[1;5X`)]).
decoded(`\e[200~hi\e[201~`, [paste("hi")]).
decoded(`\e[200~a\rb\r\nc\e[201~`, [paste("a\nb\nc")]).
decoded(`\e[200~\e[Aq\e[201~x`, [paste("\e[Aq"), x]).

test(decoded, [forall(decoded(Codes, Expected))]) :-
    codes_events_pending(Codes, Events, Pending),
    Events == Expected,
    Pending == [].

test(paste_open) :-
    codes_events_pending(`\e[200~abc\e[20`, [], Pending),
    pending_paste_open(Pending),
    \+ pending_paste_open(`\e[1;`).

test(pending, [forall(member(Codes, [`\e`, `\eO`, `\e[`, `\e[1;`, `x\e[1`, `\e[200~ab`]))]) :-
    codes_events_pending(Codes, _, Pending),
    once(append(_, Pending, Codes)),
    Pending = [27 | _].

test(flushed) :-
    pending_events_flushed(`\e`, [escape]),
    pending_events_flushed(`\e[`, [alt+'[']),
    pending_events_flushed(`\eO`, [alt+shift+o]),
    pending_events_flushed(`\e[1;`, [unknown_input(`\e[1;`)]).

:- end_tests(input).
