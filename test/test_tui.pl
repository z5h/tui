:- module(test_tui, []).

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
    Es2 == [scroll-(0-(-4))].

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

:- end_tests(substrate).


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
