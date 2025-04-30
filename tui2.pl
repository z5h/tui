:- module(tui2,
          [ render/3,
            op(601, xfy, '.>'),
            op(601, xfy, '.\\/'),
            clear_screen/0,
            hide_cursor/0,
            show_cursor/0,
            set_cursor/2,
            wait_for_input/0,
            get_single_input/1,
            reset/0
          ]).

:- use_module(local(core/core)).
:- use_module(library(ansi_term)).

:- op(601, xfy, '.>').
:- op(601, xfy, '.\\/').


                /*******************************
                *          UTILITIES           *
                *******************************/

reset :-
    format('\ec').

hide_cursor :-
    format('\e[?25l').

show_cursor :-
    format('\e[?25h').

clear_screen :-
    reset.

set_cursor(X,Y) :-
    format('\e[~w;~wH',[Y,X]).

is_stlye_attribute(A) :-
    member(A, [reset,
               bold,
               italic,
               underline,
               negative,
               bold,
               faint,
               crossed_out]).

is_color_attribute(A) :-
    ( A = fg(Color)
    ; A = bg(Color)
    ; A = hbg(Color)
    ; A = hfg(Color)
    ), my_color(Color).

ansi_attribute(A) :- is_stlye_attribute(A).

ansi_attribute(A) :- is_color_attribute(A).

is_attribute(hide_cursor).

is_attribute(style_hovergroup(Style, _G)) :-
    maplist(ansi_attribute, Style).

is_attribute(A) :-
    ansi_attribute(A).


my_color(_).

repeat_char_string(N, C, S) :-
    length(List, N),
    maplist(=(C), List),
    string_chars(S, List).

string_length_adjusted(S, L, A) :-
    string_length(S, SL),
    (  SL = L
    -> A = S

    ;  SL < L
    -> Dif is L - SL,
       repeat_char_string(Dif, ' ', Pad),
       string_concat(S, Pad, A)

    ;  length(AC, L),
       string_chars(S, SC),
       append(AC, _, SC),
       string_chars(A, AC)
    ).

                /*******************************
                *           COMMANDS           *
                *******************************/


%!  command(+Command).
%
%   True if Command is a valid drawing command.
%   Commands are the fundamental unit of drawing to the terminal.
command((X-Y)-(Stack-Attrs-C)) :-
    integer(X),
    integer(Y),
    is_list(Attrs),
    is_list(Stack),
    maplist(is_attribute, Attrs),
    atom(C),
    atom_length(C, 1).


%!  commands_end(+Commands, -End)
%
%   End = X-Y where
%   X is the max X found in Commands, and
%   Y is the max Y found in Commands.
locatables_end((X-Y)-(_-_-_), X-Y).
locatables_end((X-Y), X-Y).

locatables_end([], 0-0).
locatables_end([H|T], X3-Y3) :-
    locatables_end(H, X1-Y1),
    locatables_end(T, X2-Y2),
    Y3 is max(Y1, Y2),
    X3 is max(X1, X2).


%!  translate_command_translated(+Delta, +C0, -C1).
%
%   Translates a drawing command by Delta in the form of DX-DY.
translate_command_translated(DX-DY, (X-Y)-(Stack-Attr-C), (X1-Y1)-(Stack-Attr-C)) :-
    X1 is X + DX,
    Y1 is Y + DY.

%!  attrs_command_styled(+AttrsOuter, +C0, -C1).
%
%   Calculates the result of C0s attributes in the context of
%   surrounding attributes AttrsOuter, and stores the result in
%   the attributes of C1.
attrs_command_styled(Attrs, (X-Y)-(Stack-Inner-C), (X-Y)-(Stack-[Attrs | Inner]-C)).

/*
attrs_old_new([], A, A).
attrs_old_new([H|T], O, N) :-
    attr_old_new(H, O, N1),
    attrs_old_new(T, N1, N).

attr_old_new(reset, _, [reset]) :- !.

attr_old_new(-A, Old, New) :- !,
    @ exclude(=(A), Old, New).

attr_old_new(id(C), Old, [id(C) | N]) :- !,
    attr_old_new(-id(_), Old, N).

attr_old_new(fg(C), Old, [fg(C) | N]) :- !,
    attr_old_new(-fg(_), Old, N).

attr_old_new(bg(C), Old, [bg(C) | N]) :- !,
    attr_old_new(-bg(_), Old, N).

attr_old_new(hbg(C), Old, [hbg(C) | N]) :- !,
    attr_old_new(-hbg(_), Old, N).

attr_old_new(hfg(C), Old, [hfg(C) | N]) :- !,
    attr_old_new(-hfg(_), Old, N).

attr_old_new(A, O, N) :-
    append(O, [A], N).
*/

%!  port_visible(+Bounds, +Command).
%
%   True if the Command is for a location within the W-H Boundaries.
port_visible(W-H, (X-Y)-(_-_-_)) :-
    X > -1, X < W,
    Y > -1, Y < H.

:- meta_predicate mapnestedlist(2, ?, ?).
mapnestedlist(F, [H|T], [FH|FT]) :- !,
    mapnestedlist(F, H,FH),
    mapnestedlist(F, T,FT).

mapnestedlist(_, [], []) :- !.
mapnestedlist(F, D, FD) :-
    call(F,D,FD), !.


%!  drawable_command(+D, -C).
%
%   Converts a drawable (which may recursively consist of lists of
%   drawables) to a command (which may be a unit command or nested list
%   of commands).
%
%   X-Y-A is a drawable, where A is an atom, string or number.
%   A is a drawable equivalent to 0-0-A.
%   translate(DX-DY, Drawable) is drawable if Drawable is drawable.
%   port(W-H, Drawable) is drawable if Drawable is drawable.
%   style(Attrs, Drawable) is drawable if Drawable is drawable.
%   raw(Drawable) is drawable if Drawable is drawable.
%   Alias is drawable, if alias_drawable(Alias,Drawable)is true, and Drawable
%   is srawable.
:- discontiguous(drawable_command/2).

drawable_command(V, _) :-
    var(V), !,
    instantiation_error(drawable_command).

drawable_command([H|T], [CH|CT]) :- !,
    drawable_command(H,CH),
    drawable_command(T, CT).

drawable_command([], []) :- !.

drawable_command((X-Y)-A, Command) :-
    ( atom(A), atom_chars(A, Chars)
    ; string(A), string_chars(A, Chars)
    ; number(A), number_chars(A, Chars)
    ),
    sequence_at_command(Chars, X-Y, Command), !.

drawable_command(A, Command) :-
    ( atom(A), atom_chars(A, Chars)
    ; string(A), string_chars(A, Chars)
    ; number(A), number_chars(A, Chars)
    ),
    sequence_at_command(Chars, 0-0, Command), !.

drawable_command(raw(C), C) :- !.

sequence_at_command([], _, []).
sequence_at_command([C|R], X-Y, [(X-Y)-([]-[]-C)|SR]) :-
    X1 is X + 1,
    sequence_at_command(R, X1-Y, SR).


drawable_command(translate(DX-DY, Drawables), Translated) :- !,
    mapnestedlist(drawable_command, Drawables, Commands),
    flatten(Commands, Flattened),
    maplist(translate_command_translated(DX-DY), Flattened, Translated).

drawable_command(port(W-H, Drawables), Visible) :- !,
    mapnestedlist(drawable_command, Drawables, Commands),
    flatten(Commands, Flattened),
    include(port_visible(W-H), Flattened, Visible).

drawable_command(style(Attrs, Drawables), Styled) :- !,
    mapnestedlist(drawable_command, Drawables, Commands),
    flatten(Commands, Flattened),
    maplist(attrs_command_styled(Attrs), Flattened, Styled).

push_stack(R, (X-Y)-(Stack-Attr-C), (X-Y)-([R|Stack]-Attr-C)).


drawable_command(A .> B, Drawable) :- !,
    drawable_command(A, AC),
    locatables_end(AC, X-_Y),
    X1 is X + 1,

    drawable_command(translate(X1-0, B), BC),
    Drawable = [AC, BC].

drawable_command(A .\/ B, Drawable) :- !,
    drawable_command(A, AC),
    locatables_end(AC, _X-Y),
    Y1 is Y + 1,

    drawable_command(translate(0-Y1, B), BC),
    Drawable = [AC, BC].


drawable_command(A, C) :-
    alias_drawable(A, D), !,
    drawable_command(D, C0),
    mapnestedlist(push_stack(A), C0, C).


drawable_command(D, _) :-
    domain_error(drawable_command, D).

                /*******************************
                *            RENDER            *
                *******************************/

onscreen(X-Y) :-
    X > 0,
    Y > 0.

better_delete(L0, E, L1) :-
    append([Pre, [E], Post], L0),
    append(Pre, Post, L1), !.

apply_hover([H|T], [H|HovT]) :-
    apply_hover(T, HovT).

raw_attributes_attributes([], []).

raw_attributes_attributes([style_hovergroup(_, false)|T], Attr) :-
    raw_attributes_attributes(T, Attr).

raw_attributes_attributes([style_hovergroup(S, true)|T],  Attr) :-
    append(S,T,ST),
    raw_attributes_attributes(ST, Attr).

raw_attributes_attributes([H|T], [H|A]) :-
    raw_attributes_attributes(T, A).

apply_focus(X-Y, Commands) :-
    member((X-Y)-(_-Attr-_), Commands),
    member([style_hovergroup(S, G)], Attr),
    G = true.

apply_focus(_, _).

commandpred(P, (X1-Y1)-_, (X2-Y2)-_) :-
    compare(P, Y1-X1, Y2-X2).

drawable__normalized_commands(Drawables, Deduped) :-
    drawable_command(translate(1-1, Drawables), Commands),
    keylist_deduped_prioritize_last(Commands, Deduped).

render(X-Y, Drawables, EventAssoc) :-
    hide_cursor,
    drawable__normalized_commands(Drawables, Commands),
    once(apply_focus(X-Y, Commands)),
    render_commands(X-Y, Commands),
    commands_eventmap(Commands, EventMap),
    list_to_assoc(EventMap, EventAssoc).

commands_eventmap([], []).
commands_eventmap([((X-Y)-(S-_-_))|T], EM) :-
    (  onscreen(X-Y)
    -> E = (X-Y)-S,
       EM = [E|EMT]
    ;  EM = EMT
    ),
    commands_eventmap(T, EMT).


render_commands(_, []).
render_commands(Cursor, [((X-Y)-(_-A-C))|T]) :-
    (  onscreen(X-Y)
    -> set_cursor(X, Y),
       flatten(A, A1),
       raw_attributes_attributes(A1, A2),!,
       (   Cursor = X-Y
       ->  append(A2, [negative], A3)
       ;   A3 = A2
       ),
       location_style_char(X-Y, A3, C)
    ;  true
    ),
    render_commands(Cursor, T).

:- dynamic event_count/2.
event_counter(E, C) :-
    (  event_count(E, C0)
    -> C is C0 + 1,
       retractall(event_count(E, _))
    ;  C = 1
    ),
    assertz(event_count(E, C)).

event_counter_reset :-
    retractall(event_count(_, _)).

:- dynamic location_style_char_/3.

location_style_char_reset :-
    retractall(location_style_char_(_, _, _)).

location_style_char(X-Y, Style, C) :-
    location_style_char_(X-Y, Style, C), event_counter(skip_draw, _), !.

location_style_char(X-Y, Style, C) :-
    retractall(location_style_char_(X-Y, _, _)),
    set_cursor(X, Y),
    ansi_format(Style,'~s', [C]),
    event_counter(ansi_draw, _),
    assertz(location_style_char_(X-Y, Style, C)), !.



                /*******************************
                *     UNICODE LINES/BOXES      *
                *******************************/

char_from_to_line(C, X1-Y, X2-Y, L) :-
    X1 > X2, !,
    char_from_to_line(C, X2-Y, X1-Y, L).

char_from_to_line(C, X-Y, X-Y, [(X-Y)-C]) :- !.

char_from_to_line(C, X1-Y, X2-Y, [(X1-Y)-C|L]) :-
    Next is X1 + 1,
    char_from_to_line(C, Next-Y, X2-Y, L).


char_from_to_line(C, X-Y1, X-Y2, L) :-
    Y1 > Y2, !,
    char_from_to_line(C, X-Y2, X-Y1, L).

char_from_to_line(C, X-Y1, X-Y2, [(X-Y1)-C|L]) :-
    Next is Y1 + 1,
    char_from_to_line(C, X-Next, X-Y2, L).


:- discontiguous style_corner_char/3.
:- discontiguous style_horizontal/2.
:- discontiguous style_vertical/2.

style_corner_char(thick, tl, '\u250f').
style_corner_char(thick, bl, '\u2517').
style_corner_char(thick, tr, '\u2513').
style_corner_char(thick, br, '\u251b').
style_horizontal(thick, '\u2501').
style_vertical(thick, '\u2503').

style_corner_char(thin, tl,  '\u250c').
style_corner_char(thin, bl,  '\u2514').
style_corner_char(thin, tr,  '\u2510').
style_corner_char(thin, br,  '\u2518').
style_horizontal(thin, '\u2500').
style_vertical(thin,   '\u2502').


style_corner_char(double, tl, '\u2554').
style_corner_char(double, tr, '\u2557').
style_corner_char(double, bl, '\u255a').
style_corner_char(double, br, '\u255d').
style_horizontal(double, '\u2550').
style_vertical(double, '\u2551').


                /*******************************
                *     ALIASES (COMPONENTS)     *
                *******************************/


:- discontiguous(alias_drawable/2).
alias_drawable(V, _) :-
    var(V), !,
    instantiation_error(alias_drawable).

alias_drawable(hover(Style, Term), HoverTerm) :-
    HoverTerm = style([style_hovergroup(Style, _G)], Term).


alias_drawable(X-Y-Term, translate(X-Y, Term)) :-
    integer(X), integer(Y),
    functor(Term, Name, Arity),
    Name \= '-',
    Arity > 0, !.

alias_drawable(check(Bool), D) :-
    (  Bool = true
    -> D = style([negative,bold],0-0-'[x]')
    ;  D = style([negative,bold],0-0-'[ ]')
    ).

alias_drawable(input(W, PlaceholderA, ValueA), D) :-
    atomics_to_string([PlaceholderA], Placeholder),
    (  var(ValueA)
    -> string_length_adjusted(Placeholder, W, Displayed),
       Field = style([underline, faint], 0-0-Displayed)
    ;  atomics_to_string([ValueA], Value),
       string_length_adjusted(Value, W, Displayed),
       Field = style([underline], 0-0-Displayed)
    ),
    D = [style([faint], 0-0-'> '),
         2-0-Field].


alias_drawable(box(W0-H0, Style), [Top, Bottom, Left, Right, Corners]) :-
    W is W0 - 1,
    H is H0 - 1,
    style_corner_char(Style, tl, TL),
    style_corner_char(Style, tr, TR),
    style_corner_char(Style, bl, BL),
    style_corner_char(Style, br, BR),
    style_horizontal(Style, Hoz),
    style_vertical(Style, Vrt),
    Corners = [(0-0)-TL, (W-0)-TR, (0-H)-BL, (W-H)-BR],
    WM is W - 1,
    HM is H - 1,
    char_from_to_line(Hoz, 1-0, WM-0,  Top),
    char_from_to_line(Hoz, 1-H, WM-H,  Bottom),
    char_from_to_line(Vrt, 0-1,  0-HM, Left),
    char_from_to_line(Vrt, W-1,  W-HM, Right).


alias_drawable(frame(W-H, Contents), [Clear, Box, Port]) :-
    (  W > 1, H > 1
    -> true
    ;  domain_error(valid_window_size, W-H)
    ),
    Box = box(W-H, thin),
    PW is W - 2,
    PH is H - 2,
    Clear = 1-1-clear(PW-PH),
    Port =  1-1-port(PW-PH, Contents).

title_l('\u2574').
title_r('\u2576').

alias_drawable(frame(W-H, Title, Contents), [FramePart, 1-0-TitlePart]) :-
    title_l(TL),
    title_r(TR),
    FramePart = frame(W-H, Contents),
    string_length(Title, TitleLength),
    MaxTitleLength is W - 2,
    (  TitleLength > MaxTitleLength
    -> string_length_adjusted(Title, MaxTitleLength, TitleText),
       TitlePart = TL .> style([bold], TitleText) .> TR
    ;  TitlePart = TL .> style([bold], Title) .> TR
    ).

portd_contentd_contento_style_drawable(PD, CD, _, S, D) :-
    PD >= CD, !,
    nofm_seg_style_drawable(0/PD, (-1)-(-1), S, D).

portd_contentd_contento_style_drawable(PD, CD, CO, S, D) :-
    (P1 is abs(CO)/CD),
    (P2 is P1 + PD/CD),
    nofm_seg_style_drawable(0/PD, P1-P2, S, D).

overlap(A-B, C-D) :-
    ( A >= C, A =< D
    ; B >= C, B =< D
    ; C >= A, C =< B
    ; D >= A, D =< B
    ), !.

scroll_char(h, s, s, '\u2500').
scroll_char(h, f, f, '\u2501').
scroll_char(h, s, f, '\u257c').
scroll_char(h, f, s, '\u257e').

scroll_char(v, s, s, '\u2502').
scroll_char(v, f, f, '\u2503').
scroll_char(v, s, f, '\u257d').
scroll_char(v, f, s, '\u257f').


nofm_seg_style_drawable(M/M, _, _, []) :- !.
nofm_seg_style_drawable(N/M, P1-P2, S, [X-Y-H|T]) :-
% 0-based cell spans from N - N + 1
    % if N+0   to N+0.5 OVERLAPS seg, it's indicated
    % if N+0.5 to N+1   OVARLAPS seg, THAT part is indicated
    N0 is N/M,
    Np5 is (N + 0.5)/M,
    N1 is (N + 1)/M,
    (  overlap(N0-Np5, P1-P2)
    -> A = f
    ;  A = s
    ),
    (  overlap(Np5-N1, P1-P2)
    -> B = f
    ;  B = s
    ),
    scroll_char(S, A, B, H),
    (  S = h
    -> X = N, Y = 0
    ;  Y = N, X = 0
    ),
    Next is N + 1,
    nofm_seg_style_drawable(Next/M, P1-P2, S, T).


alias_drawable(scroll(W-H, X-Y-Content), [FramePart, 1-HM1-HScroll, WM1-1-VScroll]) :-
    HM1 is H - 1,
    WM1 is W - 1,
    drawable_command(Content, CC),
    locatables_end(CC, CW-CH),
    FramePart = frame(W-H, X-Y-raw(CC)),
    PH is H - 2,
    PW is W - 2,
    portd_contentd_contento_style_drawable(PW, CW, X, h, HScroll),
    portd_contentd_contento_style_drawable(PH, CH, Y, v, VScroll).


alias_drawable(clear(W-H), style([reset, bg(default)], Spaces)) :-
    findall((X-Y)-' ',
            ( between(0, W, X),
              between(0,H,Y)),
            Spaces).


codes_value(I, V) :-
    escape_codes_value(I, V).

escape_codes_value([27, 91 | Codes], V) :-
    atom_codes(Atom, Codes),
    escaped_atom_value(Atom, V).

escaped_atom_value('1~', home).
escaped_atom_value('2~', insert).
escaped_atom_value('3~', delete).
escaped_atom_value('4~', end).
escaped_atom_value('5~', page_up).
escaped_atom_value('6~', page_down).
escaped_atom_value('A',  up).
escaped_atom_value('B',  down).
escaped_atom_value('C',  right).
escaped_atom_value('D',  left).
escaped_atom_value('F',  end).
escaped_atom_value('H',  home).
escaped_atom_value('OP',  f1).
escaped_atom_value('OQ',  f2).
escaped_atom_value('OR',  f3).
escaped_atom_value('OS',  f4).
escaped_atom_value('15~', f5).
escaped_atom_value('17~', f6).
escaped_atom_value('18~', f7).
escaped_atom_value('19~', f8).
escaped_atom_value('20~', f9).
escaped_atom_value('21~', f10).
escaped_atom_value('23~', f11).
escaped_atom_value('24~', f12).
escaped_atom_value('25~', f13).
escaped_atom_value('26~', f14).
escaped_atom_value('28~', f15).
escaped_atom_value('29~', f16).

code_cntrl(1,   start_of_heading).
code_cntrl(2,   start_of_text).
code_cntrl(3,   interrupt).
code_cntrl(4,   eof).
code_cntrl(5,   enquiry).
code_cntrl(6,   acknowledge).
code_cntrl(7,   bell).
code_cntrl(8,   backspace).
code_cntrl(9,   tab).
code_cntrl(10,  linefeed).
code_cntrl(11,  vertical_tab).
code_cntrl(12,  formfeed).
code_cntrl(13,  return).
code_cntrl(24,  cancel).
code_cntrl(14,  shift_out).
code_cntrl(15,  shift_in).
code_cntrl(19,  device_control_3).
code_cntrl(20,  device_control_4).
code_cntrl(27,  escape).
code_cntrl(127, delete).

code_value(C,V) :- code_cntrl(C, V).

code_value(C, V) :-
    \+ code_type(C, cntrl),
    char_code(V, C).

code_value(C,V) :-
    is_list(C),
    atom_codes(V, C).


limits_direction_from_to(_-_, up, X-Y0, X-Y) :-
    Y is max(1, Y0 - 1).

limits_direction_from_to(_-_, left, X0-Y, X-Y) :-
    X is max(1, X0 - 1).

limits_direction_from_to(MX-_, right, X0-Y, X-Y) :-
    X is min(MX, X0 + 1).

limits_direction_from_to(_-MY, down, X-Y0, X-Y) :-
    Y is min(MY, Y0 + 1).

direction(E):- member(E, [up,down,left,right]).

wait_for_input :-
    get_single_input(_).

:- dynamic(last_tick/1).
input_or_tick(E) :-
    ( last_tick(Last), ! ; Last = 0),
    get_time(Now),
    (  Now - Last < 1, get_single_input(E, false)
    -> true
    ;  retractall(last_tick(_)),
       assertz(last_tick(Now)),
       E = time(T),
       format_time(atom(T), '%T', Now)
    ).


get_single_input(I) :-
    get_single_input(I, true).

get_single_input(I, Wait) :-
    (  Wait = false
    -> catch(call_with_time_limit(1, get_single_char(H)),
             time_limit_exceeded,
             true
            )
    ;  get_single_char(H)
    ),
    (  H = -1
    -> fail

    ;  H \= 27
    -> code_value(H, I)
    ;  (  \+ wait_for_input([user_input], [user_input], -1)
       -> code_value(27, I)

       ;  peek_code(27)
       -> get_code(_),
          code_value(27, I)

       ;  read_escseq([ 27 | T ]-T, I)
       -> true
       )
    ), !.


read_escseq(L-T, Code) :-
    get_code(C),
    ( T = [C], codes_value(L, Code)
    -> true
    ;  wait_for_input([user_input], [user_input], -1)
    -> T = [C | T2],
       read_escseq(L-T2, Code)
    ;  T = [],
       Code = L
    ).


stack_event_is([H|T], E, Is) :-
    (  at_event_is(H, E, Next)
    -> stack_event_is(T, Next, Is)
    ;  stack_event_is(T, E, Is)
    ).

stack_event_is([], E, Is) :-
    at_event_is([], E, Is).

stack_event_is([], E, E).


at_event_is(_, _, _) :- fail.

init((1-1)-none).
model_view((X-Y)-Last, V) :-
    format(atom(A), 'cursor: ~w', (X-Y)),
    format(string(B), 'event:  ~w', Last),

    V = frame(90-10,
              'terminal application',
              1-1-(style([faint],
                         style([reset], okok)
                         .\/
                         hover([reset, fg(green), bold], '> ' .> style([reset, fg(yellow)], A))
                         .\/
                         hover([reset, fg(green), bold], '> ' .> style([reset], B))
                        )
                  )
             )
    .>
    hover([fg(red)], (-5)-5-frame(10-10, prolog, ok)).

model_cursor((X-Y)-_, X-Y).


at_event_is([], move(_D,_F,T), update(cursor(T))).

at_event_is([], q, quit).
at_event_is([], E, update(event(E))).

go :-
    location_style_char_reset,
    event_counter_reset,
    init(Model),
    clear_screen,
    with_tty_raw(event_loop(Model)).

stream_end([H | T],  E) :-
    (  var(T)
    -> E = [H | T]
    ;  stream_end(T, E)
    ).


update(cursor(C), _-L, C-L).
update(event(E), C-_, C-E).

%update(_, Model, Model).

render_loop(End) :-
    End == [].

render_loop(ModelStream) :-
    wait(nonvar(ModelStream),
         (stream_end(ModelStream, [Model | NextStream]),
          render_model(Model),
          render_loop(NextStream)
         )).


event_loop(Model) :-
    model_cursor(Model, X-Y),
    model_view(Model, View),
    render(X-Y, View, EventMap),
    nl,
    input_or_tick(RawEvent),


    % interpret raw direction events
    (  direction(RawEvent)
    -> assoc_to_keys(EventMap, Locations),
       locatables_end(Locations, Limits),
       limits_direction_from_to(Limits, RawEvent, X-Y, X1-Y1),
       Event = move(RawEvent, X-Y, X1-Y1)
    ;  Event = RawEvent
    ),


    (  get_assoc(X-Y, EventMap, List)
    -> reverse(List, Stack)
    ;  Stack = []
    ),

    once(stack_event_is(Stack, Event, Is)),

    (  Is = quit
    -> reset,
       countall(location_style_char_(_,_,_), C),
       writeln(cached_locations:C),
       findall(Ev:Co, event_count(Ev, Co), ECs),
       writeln(ECs),
       location_style_char_reset


    ;  Is = update(Something)
    -> update(Something, Model, Next), !,
       event_loop(Next)

    ;  domain_error(known_event, Is)
    ).
