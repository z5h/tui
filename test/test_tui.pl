:- module(test_tui, []).

/** <module> Tests of library(tui)

    swipl -p library=prolog -g "consult('test/test_tui.pl'), run_tests" -t halt

Apps are tested headless, against the VCR substrate (see tui/vcr.pl).
The doc unit runs test/doc_check.pl, which checks that the
documentation is PLDoc.
*/

:- use_module(library(plunit)).
:- use_module(library(tui)).
:- use_module(library(tui/assocs)).
:- use_module(library(tui/utils)).
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

test(pairs_all) :-
    assocs_pairs([a-1, b-2, c-3], [c-3, a-1]).

test(pairs_partial_match) :-
    assocs_pairs([a-1, b-2], [a-V]),
    V == 1.

test(pairs_missing, [fail]) :-
    assocs_pairs([a-1, b-2], [a-1, c-_]).

test(pairs_empty) :-
    assocs_pairs([a-1], []).

test(pair_assocs_add, [nondet]) :-
    assocs_pair_assocs([a-1], b-2, R),
    R == [b-2, a-1].

test(pair_pair_update) :-
    pair_pair_assocs_assocs(a-_, a-99, [a-1, b-2], R),
    R == [a-99, b-2].

test(pair_pair_in_place) :-
    pair_pair_assocs_assocs(b-_, b-99, [a-1, b-2, c-3], R),
    R == [a-1, b-99, c-3].

test(pair_pair_change_key) :-
    pair_pair_assocs_assocs(a-_, x-99, [a-1, b-2], R),
    R == [x-99, b-2].

test(pair_pair_missing, [fail]) :-
    pair_pair_assocs_assocs(c-_, c-99, [a-1, b-2], _).

:- end_tests(assocs).


:- begin_tests(utils).

test(mapindexed_basic) :-
    mapindexed([I, X, I-X]>>true, [a, b, c], R),
    R == [1-a, 2-b, 3-c].

test(mapindexed_empty) :-
    mapindexed([_, _, _]>>true, [], R),
    R == [].

% Every goal is called, whatever the ones before it do; failures and
% exceptions are warnings.
test(goals_attempted) :-
    with_output_to(string(Warnings),
                   setup_call_cleanup(
                       ( set_stream(user_error, alias(saved_error)),
                         set_stream(current_output, alias(user_error)) ),
                       goals_attempted([ nb_setval(attempted, [1]),
                                         fail,
                                         ( nb_getval(attempted, A1), nb_setval(attempted, [2 | A1]) ),
                                         throw(oops),
                                         ( nb_getval(attempted, A2), nb_setval(attempted, [3 | A2]) ) ]),
                       set_stream(saved_error, alias(user_error)))),
    nb_getval(attempted, A),
    A == [3, 2, 1],
    once(sub_string(Warnings, _, _, _, "goal failed: fail")),
    once(sub_string(Warnings, _, _, _, "oops")).

:- end_tests(utils).


:- begin_tests(drawables).

test(atom_renders) :-
    drawable_raw(hi, raw(Cmds)),
    length(Cmds, 2).

% Atoms are always text, even one with an alias clause; an alias without
% arguments is written name().
:- multifile tui:alias_drawable/2.

tui:alias_drawable(test_atom_alias, "never").
tui:alias_drawable(test_zero_alias(), "xyz").

test(atom_is_text) :-
    drawable_raw(test_atom_alias, raw(Cmds)),
    length(Cmds, 15).

test(zero_arity_alias) :-
    drawable_raw(test_zero_alias(), raw(Cmds)),
    findall(C, member(_-(_-_-C), Cmds), Cs),
    Cs == [x, y, z],
    Cmds = [_-(Stack-_-_) | _],
    memberchk(_-test_zero_alias(), Stack).

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
    drawable_raw(clear(3-2), raw(Cmds)),
    length(Cmds, 6).

% The text D draws, a string per row from 0-0 to the furthest cell.
drawable_lines(D, Lines) :-
    drawable_raw(D, raw(Cmds)),
    aggregate_all(max(X), member((X-_)-_, Cmds), MX),
    aggregate_all(max(Y), member((_-Y)-_, Cmds), MY),
    findall(Line,
            ( between(0, MY, Y),
              findall(C, ( between(0, MX, X),
                           (   memberchk((X-Y)-(_-_-C), Cmds)
                           ->  true
                           ;   C = ' '
                           ) ),
                      Cs),
              string_chars(Line, Cs) ),
            Lines).

test(unknown, [throws(error(domain_error(drawable, nonsense(1)), _))]) :-
    drawable_raw("a" .> nonsense(1), _).

test(unbound, [throws(error(instantiation_error, _))]) :-
    drawable_raw(["a", _], _).

test(zone_extent) :-
    drawable_lines(zone(3-2, "a") .> "b", Lines),
    Lines == ["a  b"].

test(zone_aligns) :-
    drawable_lines(zone(5-3, [align(up_left, a), [align(center, b)], align(down_right, c)]), Lines),
    Lines == ["a    ",
              "  b  ",
              "    c"].

test(zone_overflow) :-
    drawable_raw(zone(2-1, align(right, "abc")), raw(Cmds)),
    Cmds = [(X-0)-_ | _],
    X == -1.

test(align_outside_zone) :-
    drawable_lines(align(right, "x") .> "y", Lines),
    Lines == ["xy"].

test(table_thin) :-
    drawable_lines(table(thin, [["Name", align(right, "Qty")],
                                ["apples", align(right, 12)],
                                ["kiwi"]]), Lines),
    Lines == ["┌──────┬───┐",
              "│Name  │Qty│",
              "├──────┼───┤",
              "│apples│ 12│",
              "├──────┼───┤",
              "│kiwi  │   │",
              "└──────┴───┘"].

test(table_space) :-
    drawable_lines(table(space, [[a, bb], [ccc]]), Lines),
    Lines == ["a   bb",
              "      ",
              "ccc   "].

test(table_empty) :-
    drawable_lines(table(empty, [[a, bb], [ccc, d]]), Lines),
    Lines == ["a  bb",
              "cccd "].

test(table_no_cells) :-
    drawable_raw(table(thin, []), raw(Cmds)),
    Cmds == [].

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
    app((1-1)-[], vcr_view, vcr_update, Result, [substrate(vcr(Script))]),
    Result == (2-1)-[a, terminal_size(10, 3)].

% The view places the cursor, over whatever update supplied.
cursor_view(_, "ab" .> cursor("c")).

test(view_places_cursor) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(1-1)-([]-[a, b]), (3-1)-([negative]-[c])]))
             ],
    app((1-1)-[], cursor_view, vcr_update, _, [substrate(vcr(Script))]).

% No cursor: nothing highlighted, and arrows reach update unmoved.
test(no_cursor) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(1-1)-([]-[h, i])])),
               send([right])
             ],
    app(_-[], vcr_view, vcr_update, Result, [substrate(vcr(Script))]),
    Result = Cursor-Events,
    \+ ground(Cursor),
    Events == [right, terminal_size(10, 3)].

% A cursor where nothing is drawn shows as a highlighted space.
gap_view(_, ["a", 2-0-"c"]).

test(cursor_on_nothing) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(1-1)-([]-[a]), (2-1)-([negative]-[' ']), (3-1)-([]-[c])]))
             ],
    app((2-1)-[], gap_view, vcr_update, _, [substrate(vcr(Script))]).

% What is no longer drawn is erased; what is drawn over is not.
shrinking_view(_-Es, "AB") :-
    memberchk(x, Es), !.
shrinking_view(_, "abcd").

test(erased) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(1-1)-([]-[a, b, c, d])])),
               send([x]),
               expect(runs([(1-1)-([]-['A', 'B']), (3-1)-([]-[' ', ' '])]))
             ],
    app(_-[], shrinking_view, vcr_update, _, [substrate(vcr(Script))]).

% The view is drawn in a zone the size of the terminal.
corner_view(_, align(down_right, "x")).

test(aligned_to_terminal) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(10-3)-([]-[x])]))
             ],
    app(_-[], corner_view, vcr_update, _, [substrate(vcr(Script))]).

% A view and update that leave choicepoints: the loop takes only their
% first solutions, so the choicepoint stack stays the same from event to
% event (it grew by two a batch, until the stack ran out).
leaky_view(_, "x").
leaky_view(_, "y").

leaky_update(eos, S, result(S)) :- !.
leaky_update(_, C-Chs, C-[Ch | Chs]) :-
    prolog_current_choice(Ch).
leaky_update(_, S, S).

test(no_choicepoints_kept) :-
    length(Sends, 50),
    maplist(=(send([a])), Sends),
    Script = [send([terminal_size(10, 3)]), expect(clear), expect(runs([(1-1)-([]-[x])])) | Sends],
    app(_-[], leaky_view, leaky_update, _-Chs, [substrate(vcr(Script))]),
    sort(Chs, Distinct),
    length(Distinct, 1).

% A failing update or view is an error carrying the state, raised after
% the substrate is restored; the caller can carry on from that state.
picky_update(terminal_size(_, _), S, S).
picky_update(a, C-Es, C-[a | Es]).
picky_update(eos, S, result(S)).

test(update_failed, [error(tui_callback_failed(update(b), (1-1)-[a]))]) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(1-1)-([negative]-[h]), (2-1)-([]-[i])])),
               send([a, b])
             ],
    app((1-1)-[], vcr_view, picky_update, _, [substrate(vcr(Script))]).

test(resumed_after_failure) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(1-1)-([negative]-[h]), (2-1)-([]-[i])])),
               send([a, b])
             ],
    catch(app((1-1)-[], vcr_view, picky_update, _, [substrate(vcr(Script))]),
          error(tui_callback_failed(update(b), S), _),
          app(S, vcr_view, picky_update, R,
              [substrate(vcr([send([terminal_size(10, 3)]), expect(clear),
                              expect(runs([(1-1)-([negative]-[h]), (2-1)-([]-[i])])),
                              send([a])]))])),
    R == (1-1)-[a, a].

failing_view(_, _) :- fail.

test(view_failed, [error(tui_callback_failed(view, (1-1)-[]))]) :-
    app((1-1)-[], failing_view, vcr_update, _, [substrate(vcr([send([terminal_size(10, 3)]), expect(clear)]))]).

test(failure_message) :-
    phrase(prolog:translate_message(error(tui_callback_failed(update(ctrl+x), big_state), _)), Lines),
    with_output_to(string(A), print_message_lines(current_output, '', Lines)),
    once(sub_atom(A, _, _, _, 'update failed on the event ctrl+x')),
    \+ sub_atom(A, _, _, _, big_state).

% The redraw key clears and paints everything again; nothing sees it.
test(redraw) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(1-1)-([negative]-[h]), (2-1)-([]-[i])])),
               send([ctrl+l, a]),
               expect(clear),
               expect(runs([(1-1)-([negative]-[h]), (2-1)-([]-[i])]))
             ],
    app((1-1)-[], vcr_view, vcr_update, Result, [substrate(vcr(Script)), redraw(ctrl+l)]),
    Result == (1-1)-[a, terminal_size(10, 3)].

% The reload key runs make/0, then the view is drawn anew (here it reads
% a global the test changes, as changed code would draw differently),
% and update receives reloaded; the key itself reaches nothing.
global_view(_, Text) :-
    nb_getval(test_view_text, Text).

% x changes what the view draws without changing the state, as editing
% the code would, so nothing is painted until the reload.
test(reload, [ setup(nb_setval(test_view_text, "ab")),
               cleanup(nb_delete(test_view_text)) ]) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(1-1)-([negative]-[a]), (2-1)-([]-[b])])),
               send([x]),
               send([f5]),
               expect(runs([(2-1)-([]-[c])]))
             ],
    app((1-1)-[], global_view, changing_update, Result,
        [substrate(vcr(Script)), reload(f5)]),
    Result == (1-1)-[reloaded].

changing_update(x, S, S) :- !,
    nb_setval(test_view_text, "ac").
changing_update(reloaded, C-Es, C-[reloaded | Es]) :- !.
changing_update(eos, S, result(S)) :- !.
changing_update(_, S, S).

test(mismatch, [throws(error(vcr_mismatch(expect(runs(_)), expect(clear)), _))]) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(runs([]))
             ],
    app((1-1)-[], vcr_view, vcr_update, _, [substrate(vcr(Script))]).

:- end_tests(vcr).


:- begin_tests(events).

:- multifile tui:alias_drawable/2.
:- multifile tui:at_event_is/3.

% probe(D): k becomes where it hit, relative to the probe, and a move
% right; a move away from the probe is reported, with where it started.
tui:alias_drawable(probe(D), D).

tui:at_event_is(probe(_), (X-Y)-k, hit(X-Y)).
tui:at_event_is(probe(_), _-k, right).
tui:at_event_is(probe(_), (X-Y)-moved(D), moved_from(D, X-Y)).
tui:at_event_is(probe(_), (X-Y)-mouse(press, left), clicked(X-Y)).

probe_update(eos, S, result(S)) :- !.
probe_update(E, (X-Y)-Es, (X-Y)-[E | Es]).

probe_view(_, "ab" .> probe("xyz")).

% Drawn on its own, then embedded: its origin moves with it.
raw_probe_view(_, "ab" .> R) :-
    drawable_raw(probe("xyz"), R).

test(relative, [forall(member(View, [probe_view, raw_probe_view]))]) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(1-1)-([]-[a, b, x]), (4-1)-([negative]-[y]), (5-1)-([]-[z])])),
               send([k]),
               expect(runs([(1-1)-([]-[a, b, x, y]), (5-1)-([negative]-[z])]))
             ],
    app((4-1)-[], View, probe_update, Result, [substrate(vcr(Script))]),
    Result == (5-1)-[moved_from(right, 1-0), hit(1-0), terminal_size(10, 3)].

% A mouse event bubbles where it happened, not at the cursor, and a press
% moves the cursor there. Unclaimed, it reaches update with its position.
test(mouse) :-
    Script = [ send([terminal_size(10, 3)]),
               expect(clear),
               expect(runs([(1-1)-([negative]-[a]), (2-1)-([]-[b, x, y, z])])),
               send([(5-1)-mouse(press, left)]),
               expect(runs([(1-1)-([]-[a, b, x, y]), (5-1)-([negative]-[z])])),
               send([(8-2)-mouse(press, left), (1-1)-mouse(scroll, up)]),
               expect(runs([(1-1)-([]-[a, b, x, y, z]), (8-2)-([negative]-[' '])]))
             ],
    app((1-1)-[], probe_view, probe_update, Result, [substrate(vcr(Script))]),
    Result == (8-2)-[(1-1)-mouse(scroll, up), (8-2)-mouse(press, left),
                     clicked(2-0), terminal_size(10, 3)].

:- end_tests(events).


:- begin_tests(input_component).

:- use_module(library(tui/components)).

:- use_module(library(tui/drawable), [drawable__normalized_commands__end/3]).
:- use_module(library(tui/events), [point_event_assoc_bubbled/4]).

% What E at point X-Y becomes, on D drawn at 1-1.
drawable_point_event_bubbled(D, X-Y, E, Es) :-
    drawable__normalized_commands__end(D, Commands, _),
    findall(P-S, member(P-(S-_-_), Commands), Pairs),
    list_to_assoc(Pairs, Assoc),
    findall(E1, point_event_assoc_bubbled(X-Y, E, Assoc, E1), Es).

% In a table cell, measured then placed, positions stay relative to the
% component (probe/1 is in the events unit). The probe is right-aligned
% in a 5-wide column starting at x=8, so it starts at x=10.
test(in_table) :-
    drawable_point_event_bubbled(
        table(thin, [[a, align(right, probe("xyz"))], [bbbbb, wwwww]]),
        11-2, k, Es),
    Es == [hit(1-0), right].

test(click_activates) :-
    drawable_point_event_bubbled(ok : button("OK"), 2-1, mouse(press, left), Es1),
    Es1 == [ok-pressed],
    drawable_point_event_bubbled(c : check_box("C", false), 1-1, mouse(press, left), Es2),
    Es2 == [c-true].

% A 10×5 scroll of 20 lines: the port is 3 rows high, the vertical
% scrollbar is at x=10, rows 2 to 4.
lines_scroll(Offset, scroll(10-5, Offset, column(Lines))) :-
    numlist(1, 20, Ns),
    maplist([N, L]>>format(string(L), "line ~w", [N]), Ns, Lines).

test(wheel) :-
    lines_scroll(0-(-5), S),
    drawable_point_event_bubbled(S, 3-3, mouse(scroll, down), Es1),
    Es1 == [scroll-(0-(-6))],
    drawable_point_event_bubbled(S, 3-3, mouse(scroll, up), Es2),
    Es2 == [scroll-(0-(-4))],
    lines_scroll(0-0, Top),
    drawable_point_event_bubbled(Top, 3-3, mouse(scroll, up), Es3),
    Es3 == [noop].

test(thumb_to_mouse) :-
    lines_scroll(0-(-5), S),
    drawable_point_event_bubbled(S, 10-2, mouse(press, left), Es1),
    Es1 == [scroll-(0-0)],
    drawable_point_event_bubbled(S, 10-4, mouse(drag, left), Es2),
    Es2 == [scroll-(0-(-17))].

% What E at point X-Y becomes, on an input showing Value.
value_point_event_bubbled(Value, XY, E, Es) :-
    drawable_point_event_bubbled(name : input(4, "", Value), XY, E, Es).

test(typed) :-
    value_point_event_bubbled(_, 3-1, a, Es),
    Es == [name-"a", cursor_by(1-0)].

test(inserted_at_cursor) :-
    value_point_event_bubbled("ac", 4-1, b, Es),
    Es == [name-"abc", cursor_by(1-0)].

% Past the end, text goes at the end, and the cursor moves to just
% after it (here it is already there).
test(past_the_end) :-
    value_point_event_bubbled("a", 5-1, b, Es),
    Es == [name-"ab"],
    value_point_event_bubbled("a", 6-1, b, Es2),
    Es2 == [name-"ab", cursor_by((-1)-0)].

test(backspace) :-
    value_point_event_bubbled("abc", 5-1, backspace, Es),
    Es == [name-"ac", cursor_by((-1)-0)].

test(delete) :-
    value_point_event_bubbled("abc", 4-1, delete, Es),
    Es == [name-"ac"].

% With nothing to delete, the field still takes the key, to do nothing:
% noop, which the tag passes through untouched.
test(nothing_to_delete) :-
    value_point_event_bubbled(_, 3-1, backspace, Es1),
    Es1 == [noop],
    value_point_event_bubbled(_, 3-1, delete, Es2),
    Es2 == [noop],
    value_point_event_bubbled("ab", 3-1, backspace, Es3),
    Es3 == [noop],
    value_point_event_bubbled("ab", 5-1, delete, Es4),
    Es4 == [noop].

% Past the end, delete has nothing to delete but brings the cursor back.
test(delete_past_the_end) :-
    value_point_event_bubbled("a", 6-1, delete, Es),
    Es == [cursor_by((-2)-0)].

test(paste) :-
    value_point_event_bubbled("", 3-1, paste("a\nb"), Es),
    Es == [name-"a b", cursor_by(3-0)].

% Arriving past the end of the text (trailing spaces included), or on
% the prompt, the cursor moves to the nearest editable cell.
test(arrival) :-
    value_point_event_bubbled("a ", 6-1, arrived(down), Es1),
    Es1 == [cursor_by((-1)-0)],
    value_point_event_bubbled("a ", 5-1, arrived(down), Es2),
    Es2 == [arrived(down)],
    value_point_event_bubbled(_, 5-1, mouse(press, left), Es3),
    Es3 == [cursor_by((-2)-0)],
    value_point_event_bubbled("ab", 1-1, arrived(right), Es4),
    Es4 == [cursor_by(2-0)].

% Through the loop: an input under a row of digits, its field at x 3..8.
field_view(_-Value, column(["0123456789", name : input(6, "", Value)])).

field_update(name-V, C-_, C-V) :- !.
field_update(_, S, S).

% The cursor after each of Events in turn, from S0.
state_events_cursors(_, [], []).
state_events_cursors(S0, [E | Es], [C | Cs]) :-
    context_module(M),
    tui_loop:view_size_state_frame(M:field_view, 20-5, S0, F),
    tui_loop:frame_update_event_state0_state(F, M:field_update, E, S0, S),
    S = C-_,
    state_events_cursors(S, Es, Cs).

test(cursor_kept_in_text) :-
    state_events_cursors((8-1)-"ab", [down, up, (8-2)-mouse(press, left), c, right], Cs),
    Cs == [5-2, 5-1, 5-2, 6-2, 6-2].

test(on_prompt) :-
    value_point_event_bubbled("a", 1-1, b, Es),
    Es == [b].

test(not_an_edit) :-
    value_point_event_bubbled("a", 3-1, up, Es),
    Es == [up].

test(button, [forall(member(E, [' ', return]))]) :-
    drawable_point_event_bubbled(ok : button("OK"), 3-1, E, Es),
    Es == [ok-pressed].

test(check_box) :-
    drawable_point_event_bubbled(c : check_box("a", false), 1-1, ' ', Es),
    Es == [c-true].

test(clear_inside_frame) :-
    drawable__normalized_commands__end(frame(4-3, []), Commands, _),
    forall(member((X-Y)-(_-_-' '), Commands),
           ( X == 2, Y == 2 ; X == 3, Y == 2 )).

:- end_tests(input_component).


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
decoded(`\e[<0;5;3M`,       [(5-3)-mouse(press, left)]).
decoded(`\e[<0;5;3m`,       [(5-3)-mouse(release, left)]).
decoded(`\e[<2;10;200M`,    [(10-200)-mouse(press, right)]).
decoded(`\e[<32;6;3M`,      [(6-3)-mouse(drag, left)]).
decoded(`\e[<35;7;4M`,      [(7-4)-mouse(move, none)]).
decoded(`\e[<64;1;1M`,      [(1-1)-mouse(scroll, up)]).
decoded(`\e[<67;1;1M`,      [(1-1)-mouse(scroll, right)]).
decoded(`\e[<20;2;2M`,      [(2-2)-(ctrl+shift+mouse(press, left))]).
decoded([27, 0'[, 0'M, 32, 37, 35], [(5-3)-mouse(press, left)]).
decoded([27, 0'[, 0'M, 35, 37, 35], [(5-3)-mouse(release, none)]).

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

test(graphics_reply) :-
    codes_events_pending(`\e_Gi=31;OK\e\\a`, Events, Pending),
    Events == [kitty_graphics("i=31;OK"), a],
    Pending == [].

test(apc_incomplete) :-
    codes_events_pending(`a\e_Gi=31;O`, Events, Pending),
    Events == [a],
    Pending == `\e_Gi=31;O`.

test(flushed) :-
    pending_events_flushed(`\e`, [escape]),
    pending_events_flushed(`\e[`, [alt+'[']),
    pending_events_flushed(`\eO`, [alt+shift+o]),
    pending_events_flushed(`\e[1;`, [unknown_input(`\e[1;`)]).

:- end_tests(input).


:- begin_tests(substrate).

:- use_module(library(tui/wake)).

% Replies are consumed; the device attributes reply ends detection and
% becomes the terminal's properties. The Kitty push is written to output.
replies_keyboard_keys(Replies, K, Keys) :-
    with_output_to(string(_),
                   tui_substrate:keyboard_events_keys(detecting-false, Replies, K, Keys)).

test(legacy) :-
    replies_keyboard_keys([a, device_attributes([1]), b], K, Keys),
    K == legacy-false,
    Keys = [a, terminal_properties(Ps), b],
    memberchk(extended_keys(false), Ps),
    memberchk(graphics(false), Ps),
    memberchk(program(P), Ps),
    atom(P).

test(kitty) :-
    replies_keyboard_keys([kitty_keyboard(0), kitty_graphics("i=31;OK"), device_attributes([1])], K, Keys),
    K == kitty-true,
    Keys = [terminal_properties(Ps)],
    memberchk(extended_keys(true), Ps),
    memberchk(graphics(true), Ps).

test(graphics_error) :-
    replies_keyboard_keys([kitty_graphics("i=31;EINVAL:bad"), device_attributes([1])], _, Keys),
    Keys = [terminal_properties(Ps)],
    memberchk(graphics(false), Ps).

% In a terminal session, user_error is captured: what any thread writes
% is posted as stderr(Text), a line at a time; restoring posts the rest.
test(stderr_captured) :-
    wake_open(Wake),
    tui_substrate:wake_stderr_captured(Wake, Stderr),
    format(user_error, "one~n", []),
    thread_create(format(user_error, "two~n", []), T, []),
    thread_join(T, _),
    format(user_error, "three", []),
    tui_substrate:stderr_restored(Stderr),
    wake_count_timeout_events(Wake, 3, 2, Events),
    wake_close(Wake),
    Events == [stderr("one\n"), stderr("two\n"), stderr("three")].

:- end_tests(substrate).


:- begin_tests(subscriptions).

:- use_module(library(tui/subscriptions)).
:- use_module(library(tui/wake)).

% Records every event but terminal_size; quits on eos.
recording_view(_, "x").

recording_update(terminal_size(_, _), S, S) :- !.
recording_update(eos, S, result(S)) :- !.
recording_update(E, C-Es, C-Es1) :-
    append(Es, [E], Es1).

subscribed_app(Subs, Script, Events) :-
    app(_-[], recording_view, recording_update, _-Events,
        [ substrate(vcr([ send([terminal_size(10, 3)]),
                          expect(clear),
                          expect(runs([(1-1)-([]-[x])])) | Script ])),
          subscriptions(Subs) ]).

ticking(_, [every(10, tick)]).

test(every) :-
    subscribed_app(ticking, [receive(3)], Events),
    Events == [tick, tick, tick].

sender(Port) :-
    port_send(Port, a),
    port_send(Port, b).

sending(_, [thread(sender)]).

% A thread's events arrive in order; it ending by itself is an event.
test(thread) :-
    subscribed_app(sending, [receive(3)], Events),
    Events == [a, b, thread_ended(sender, true)].

failing_sender(_) :- fail.
raising_sender(_) :- throw(oops).

failing(_, [thread(failing_sender), thread(raising_sender)]).

test(thread_ended) :-
    subscribed_app(failing, [receive(2)], Events),
    msort(Events, Sorted),
    Sorted == [thread_ended(failing_sender, false), thread_ended(raising_sender, exception(oops))].

% Blocks until stopped, then reports to Q that it was.
waiter(Q, Port) :-
    setup_call_cleanup(port_send(Port, started),
                       thread_get_message(never_sent),
                       thread_send_message(Q, stopped)).

% Subscribed until it has started.
waiting_until_started(Q, _-Es, Subs) :-
    (   memberchk(started, Es)
    ->  Subs = []
    ;   Subs = [thread(waiter(Q))]
    ).

test(stopped_when_unsubscribed) :-
    message_queue_create(Q),
    subscribed_app(waiting_until_started(Q), [receive(1)], Events),
    Events == [started],
    thread_get_message(Q, stopped, [timeout(2)]),
    message_queue_destroy(Q).

waiting(Q, _, [thread(waiter(Q))]).

test(stopped_when_the_app_ends) :-
    message_queue_create(Q),
    subscribed_app(waiting(Q), [receive(1)], Events),
    Events == [started],
    thread_get_message(Q, stopped, [timeout(2)]),
    message_queue_destroy(Q).

test(unknown_subscription, [error(domain_error(tui_subscription, sometimes))]) :-
    subscribed_app([_, [sometimes]]>>true, [], _).

test(closed_port) :-
    wake_open(Wake),
    wake_close(Wake),
    port_send(port(Wake), lost).

% An unbound expectation matches any paint.
counting_view(_-Es, literal(N)) :-
    length(Es, N).

test(any_paint) :-
    app(_-[], counting_view, recording_update, _-Events,
        [ substrate(vcr([ send([terminal_size(10, 3)]), expect(clear), expect(runs(_)),
                          receive(3), expect(runs(Runs)) ])),
          subscriptions(sending) ]),
    var(Runs),
    Events == [a, b, thread_ended(sender, true)].

test(diff) :-
    running_subs_stopped_started([every(1, a)-t1, thread(g)-t2], [thread(g), every(2, a), every(2, a)], Stopped, Started),
    Stopped == [every(1, a)-t1],
    Started == [every(2, a)].

:- end_tests(subscriptions).


:- begin_tests(terminal).

% The bytes terminal.pl writes, to any stream: the VCR checks runs, these
% check what the runs become.

:- use_module(library(tui/terminal)).

goal_written(Goal, S) :-
    with_output_to(string(S), Goal).

test(run_plain) :-
    goal_written(ansi_run((3-2)-([]-[a, b])), S),
    S == "\e[2;3Hab".

test(run_styled) :-
    goal_written(ansi_run((1-1)-([bold, fg(red)]-[x])), S),
    S == "\e[1;1H\e[1;31mx\e[0m".

test(run_true_color) :-
    goal_written(ansi_run((1-1)-([fg(1, 2, 3), bg(4, 5, 6)]-[x])), S),
    S == "\e[1;1H\e[38;2;1;2;3;48;2;4;5;6mx\e[0m".

test(sgr) :-
    forall(member(Attrs-Expected,
                  [ []-'',
                    [faint, italic, underline, negative, crossed_out, reset]-'2;3;4;7;9;0',
                    [fg(default), bg(white)]-'39;47',
                    [hfg(green), hbg(yellow)]-'92;103',
                    [fg(208), bg(0)]-'38;5;208;48;5;0',
                    [bg(200, 100, 0)]-'48;2;200;100;0' ]),
           ( attributes_sgr(Attrs, SGR),
             SGR == Expected )).

test(sgr_unknown, [error(domain_error(sgr_attribute, fg(pink)))]) :-
    attributes_sgr([bold, fg(pink)], _).

test(sgr_out_of_range, [error(domain_error(sgr_attribute, fg(256)))]) :-
    attributes_sgr([fg(256)], _).

test(run_multi_codepoint_char) :-
    atom_codes(P, [0x10EEEE, 0x0305, 0x0305]),
    goal_written(ansi_run((1-1)-([]-[P, P])), S),
    atom_codes(P2, [0x10EEEE, 0x0305, 0x0305, 0x10EEEE, 0x0305, 0x0305]),
    atom_concat('\e[1;1H', P2, A),
    atom_string(A, S).

test(modes) :-
    goal_written(( ansi_hide_cursor, ansi_show_cursor, ansi_clear, ansi_reset,
                   ansi_set_cursor(10, 20) ), S),
    S == "\e[?25l\e[?25h\e[2J\ec\e[20;10H".

test(session_modes) :-
    goal_written(( ansi_bracketed_paste_on, ansi_mouse_on,
                   ansi_mouse_off, ansi_bracketed_paste_off ), S),
    S == "\e[?2004h\e[?1000h\e[?1002h\e[?1006h\e[?1006l\e[?1002l\e[?1000l\e[?2004l".

test(queries) :-
    goal_written(( ansi_kitty_keyboard_query, ansi_kitty_keyboard_push(1),
                   ansi_kitty_keyboard_pop, ansi_primary_device_attributes ), S),
    S == "\e[?u\e[>1u\e[<u\e[c".

test(graphics_query) :-
    goal_written(ansi_kitty_graphics_query, S),
    S == "\e_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\e\\".

:- end_tests(terminal).


:- begin_tests(image).

:- use_module(library(tui/image)).
:- use_module(library(tui/terminal)).

test(placeholders) :-
    drawable_raw(image(0x01022A, png("x"), 2-2), raw(Cmds)),
    Cmds = [(0-0)-(Stack-Attrs-C00) | _],
    memberchk(_-image(0x01022A, png("x"), 2-2), Stack),
    flatten(Attrs, [fg(1, 2, 42)]),
    atom_codes(C00, [0x10EEEE, 0x0305, 0x0305]),
    findall(XY-Cs, ( member(XY-(_-_-C), Cmds), atom_codes(C, [_ | Cs]) ), Cells),
    Cells == [(0-0)-[0x0305, 0x0305], (1-0)-[0x0305, 0x030D],
              (0-1)-[0x030D, 0x0305], (1-1)-[0x030D, 0x030D]].

test(sent_actions) :-
    images_sent_actions([image(1, png("a"), 2-2)], [], A1, S1),
    A1 == [transmit(1, png("a")), place(1, 2-2)],
    images_sent_actions([image(1, png("a"), 2-2)], S1, A2, S1),
    A2 == [],
    images_sent_actions([image(1, png("a"), 3-1)], S1, A3, S3),
    A3 == [place(1, 3-1)],
    images_sent_actions([image(1, png("b"), 3-1)], S3, A4, S4),
    A4 == [transmit(1, png("b")), place(1, 3-1)],
    S4 == [image(1, png("b"), 3-1)],
    images_sent_actions([], S4, A5, S5),
    A5 == [],
    S5 == S4.

test(transmit_escape) :-
    with_output_to(string(S), ansi_kitty_image_transmit(7, png("abc"))),
    S == "\e_Ga=t,f=100,i=7,q=2;YWJj\e\\".

test(transmit_chunked) :-
    length(Codes, 4000),
    maplist(=(0), Codes),
    with_output_to(string(S), ansi_kitty_image_transmit(7, rgb(10-10, Codes))),
    split_string(S, "\e", "", Parts),
    Parts = ["", First, "\\", Last, "\\"],
    sub_string(First, 0, _, _, "_Ga=t,f=24,s=10,v=10,i=7,q=2,m=1;"),
    sub_string(Last, 0, _, _, "_Gm=0,q=2;").

test(place_escape) :-
    with_output_to(string(S), ansi_kitty_image_place(7, 3-2)),
    S == "\e_Ga=p,U=1,i=7,p=1,c=3,r=2,q=2\e\\".

% The view draws an image once the terminal reports graphics; the upload
% and placement are sent once, before the runs.
image_view(_-false, "no graphics").
image_view(_-true, image(5, png("x"), 1-1)).

image_update(terminal_properties(Ps), C-_, C-G) :- !,
    memberchk(graphics(G), Ps).
image_update(eos, S, result(S)) :- !.
image_update(_, S, S).

test(vcr) :-
    atom_codes(P, [0x10EEEE, 0x0305, 0x0305]),
    Script = [ send([terminal_size(12, 2)]),
               expect(clear),
               expect(runs([(1-1)-([]-[n, o, ' ', g, r, a, p, h, i, c, s])])),
               send([terminal_properties([graphics(true)])]),
               expect(graphics([transmit(5, png("x")), place(5, 1-1)])),
               expect(runs([(1-1)-([fg(0, 0, 5)]-[P]),
                            (2-1)-([]-[' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '])])),
               send([x])
             ],
    app(_-false, image_view, image_update, _, [substrate(vcr(Script))]).

:- end_tests(image).


:- begin_tests(doc).

:- use_module(library(process)).
:- use_module(library(readutil)).

% test/doc_check.pl, in a process of its own (PLDoc collects comments
% only from files loaded after it is switched on). Its report is
% printed if there is one.
test(pldoc) :-
    module_property(test_tui, file(File)),
    file_directory_name(File, TestDir),
    file_directory_name(TestDir, Repo),
    directory_file_path(Repo, prolog, Lib),
    atom_concat('library=', Lib, LibPath),
    directory_file_path(TestDir, 'doc_check.pl', Check),
    current_prolog_flag(executable, Swipl),
    setup_call_cleanup(
        process_create(Swipl, ['-p', LibPath, Check],
                       [cwd(Repo), stdout(pipe(Out)), stderr(std), process(Pid)]),
        read_string(Out, _, Report),
        close(Out)),
    process_wait(Pid, Status),
    (   Status == exit(0)
    ->  true
    ;   format(user_error, "~s", [Report]),
        fail
    ).

:- end_tests(doc).
