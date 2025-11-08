:- module(tui,
          [ op(601, xfy, '.>'),
            op(601, xfy, '.\\/'),
            discrete/1,
            clear_screen/0,
            hide_cursor/0,
            show_cursor/0,
            set_cursor/2,
            wait_for_input/0,
            get_single_input/1,
            input_or_tick/1,
            direction/1,
            reset/0,
            tui_init/0,
            stack_event_is/3,
            locatables_end/2,
            limits_direction_from_to/4,
            drawable_raw/2,
            drawable//5,
            app/4
          ]).
:- use_module(local(core/assocs)).
:- use_module(local(core/core)).
:- use_module(library(ansi_term)).

:- multifile at_event_is/3.
:- multifile alias_drawable/2.

                /*******************************
                *       MORPH RELATIONS        *
                *******************************/

discrete(G) :-
    copy_term_nat(G, G0),
    call(G0),
    G = G0.

                /*******************************
                *          UTILITIES           *
                *******************************/
bell :-
    format('\007').

reset :-
    format('\ec').

hide_cursor :-
    format('\e[?25l').

show_cursor :-
    format('\e[?25h').

clear_screen :-
    reset.

set_cursor(X, Y) :-
    format('\e[~w;~wH', [Y, X]).

is_stlye_attribute(A) :-
    member(A, [reset,
               bold,
               italic,
               underline,
               negative,
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
locatables_end((X-Y)-(_-_-_), X-Y) :- !.
locatables_end((X-Y), X-Y) :- !.

locatables_end([], 0-0) :- !.
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
attrs_command_styled(Attrs, (X-Y)-(Stack-Inner-C), (X-Y)-(Stack-[Attrs  |Inner]-C)).

%!  port_visible(+Bounds, +Command).
%
%   True if the Command is for a location within the W-H Boundaries.
port_visible(W-H, (X-Y)-(_-_-_)) :-
    X > -1, X < W,
    Y > -1, Y < H.

:- meta_predicate mapnestedlist(2, ?, ?).
mapnestedlist(F, [H|T], [FH|FT]) :- !,
    mapnestedlist(F, H, FH),
    mapnestedlist(F, T, FT).

mapnestedlist(_, [], []) :- !.
mapnestedlist(F, D, FD) :-
    call(F, D, FD), !.

:- discontiguous(drawable//5).
:- det(drawable//5).
drawable(Var, _, _, _, _) -->
    { var(Var), !,
      domain_error(drawable, Var)
    }.

drawable(chars([]), _, _, XY, XY) --> !,
    [].

drawable(chars([C|T]), Stack, Attr, X-Y, MX-MY) --> !,
    [ (X-Y)-(Stack-Attr-C)],
    drawable(chars_tail(T), Stack, Attr, X-Y, MX-MY), !.

drawable(chars_tail([]), _, _, XY, XY) --> !,
    [].

drawable(chars_tail(T), Stack, Attr, X-Y, MX-MY) --> !,
    { NX is X + 1 },
    drawable(chars(T), Stack, Attr, NX-Y, MX-MY), !.

drawable(raw([]), _, _, XY, XY) --> !,
    [].

drawable(raw([H|T]), Stack, Attr, DX-DY, MX-MY) --> !,
    {H = (X-Y)-(StackH-AttrH-C),
    X1 is X + DX,
    Y1 is Y + DY,
    append(AttrH, Attr, Attr1),
    append(StackH, Stack, Stack1),
    H1 = (X1-Y1)-(Stack1-Attr1-C)
    }, !,
    [H1],
    drawable(raw(T), Stack, Attr, DX-DY, MTX-MTY),
    { MX is max(X1, MTX),
      MY is max(Y1, MTY)
    }.

drawable(A, Stack, Attr, X-Y, MX-MY) -->
    { atom(A), atom_chars(A, Chars)
    ; string(A), string_chars(A, Chars)
    ; number(A), number_chars(A, Chars)
    }, !,
    drawable(chars(Chars), Stack, Attr, X-Y, MX-MY).

drawable([H|T], Stack, Attr, XY, MX-MY) --> !,
    drawable(H, Stack, Attr, XY, MX1-MY1),
    drawable(T, Stack, Attr, XY, MX2-MY2),
    { MX is max(MX1, MX2), MY is max(MY1, MY2) }, !.

drawable([], _, _, XY, XY) --> !, [].

capture(Phrase, C, A, A2) :-
    phrase(Phrase, C, []), !,
    A = A2.

excluding(Pred, Phrase) -->
    capture(Phrase, C),
    { exclude(Pred, C, E) },
    E.

zone_out(X0-Y0, W-H, X-Y-_) :-
     once(( X < X0
     ; Y < Y0
     ; X >= X0 + W
     ; Y >= Y0 + H
     )).

drawable(translate(TX-TY, Drawables), Stack, Attr, DX-DY, MX-MY) --> !,
    { NDX is DX + TX, NDY is DY + TY},
    drawable(Drawables, Stack, Attr, NDX-NDY, MX-MY).

drawable(TX-TY-Drawable, Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(translate(TX-TY, Drawable), Stack, Attr, DX-DY, MX-MY).

drawable(port(W-H, Drawables), Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(port(W-H, Drawables, _MPX-_MPY), Stack, Attr, DX-DY, MX-MY).

drawable(port(W-H, Drawables, MPX-MPY), Stack, Attr, DX-DY, MX-MY) --> !,
    excluding(zone_out(DX-DY, W-H), drawable(Drawables, Stack, Attr, DX-DY, MPX-MPY)),
    { MX is DX + W - 1, MY is DY + H - 1}.

drawable(style(Style, Drawables), Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(Drawables, Stack, [Style | Attr ], DX-DY, MX-MY).

drawable(A .> B, Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(A, Stack, Attr, DX-DY, AMX-AMY),
    { WidthA is AMX - DX + 1 },
    drawable(translate(WidthA-0, B), Stack, Attr, DX-DY, BMX-BMY),
    { MX is max(AMX, BMX), MY is max(AMY, BMY) }.


drawable(A .\/ B, Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(A, Stack, Attr, DX-DY, AMX-AMY),
    { HeightA is AMY - DY + 1 },
    drawable(translate(0-HeightA, B), Stack, Attr, DX-DY, BMX-BMY),
    { MX is max(AMX, BMX), MY is max(AMY, BMY) }.

drawable(A, Stack, Attr, DX-DY, MX-MY) -->
    { tui:alias_drawable(A, D) }, !,
    drawable(D, [A | Stack], Attr, DX-DY, MX-MY).

drawable(D, _, _, _, _) -->
    { domain_error(drawable, D) }.

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

raw_attributes_attributes([style_hovergroup(S, true)|T], Attr) :-
    append(S, T, ST),
    raw_attributes_attributes(ST, Attr).

raw_attributes_attributes([H|T], [H|A]) :-
    raw_attributes_attributes(T, A).

apply_focus(X-Y, Commands) :-
    member((X-Y)-(_-Attr-_), Commands),
    member([style_hovergroup(_S, G)], Attr),
    G = true.

apply_focus(_, _).

drawable_raw(Drawable, raw(Raw)) :-
    phrase(drawable(Drawable, [], [], 0-0, _), Raw, []).

drawable__normalized_commands__end(Drawables, Deduped, MXY) :-
    phrase(drawable(Drawables, [], [], 1-1, MXY), Commands, []),
    !,
    keylist_deduped_prioritize_last(Commands, Deduped).


:- meta_predicate(app(?, 2, 3, ?)).
:- det(app/4).
app(result(Result), _, _, Result) :- !.

app(S0, View, Update, Result) :-
    @ hide_cursor,
    @ (X-Y)-M0 = S0,

    @ call(View, S0, Drawable),
    @ drawable__normalized_commands__end(Drawable, Commands, EX-EY),
    @ once(apply_focus(X-Y, Commands)),
    @ render_commands(X-Y, Commands),




    @ commands_eventmap(Commands, EventMap),
    @ list_to_assoc(EventMap, EventAssoc), !,

%    get_single_input(E0), !,
    input_or_tick(E0), !,
    state_event_assoc_bubbled(S0, E0, EventAssoc, E1),
    (  E1 = result(Result)
    -> true

    ;  direction(E1)
    -> (  limits_direction_from_to(EX-EY, E1, X-Y, NX-NY)
       -> state_event_assoc_bubbled((X-Y)-M0, moved(E1, X-Y, NX-NY), EventAssoc, E2),
          (  E2 = moved(E1, X-Y, NX-NY)
          -> app((NX-NY)-M0, View, Update, Result)
          ;  call(Update, E2, (NX-NY)-M0, S1),
             app(S1, View, Update, Result)
          )
       ;  bell,
          app(S0, View, Update, Result)
       )

    ;  call(Update, E1, S0, S1),
       app(S1, View, Update, Result)
    ).

state_event_assoc_bubbled(S0, E0, EventAssoc, E1) :-
    (X-Y)-_ = S0,
    (  get_assoc(X-Y, EventAssoc, Stack)
    -> true
    ;  Stack = []
    ),
    stack_event_is(Stack, E0, E1).

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
    -> %set_cursor(X, Y),
       flatten(A, A1),
       raw_attributes_attributes(A1, A2), !,
       (   Cursor = X-Y
       ->  append(A2, [negative], A3)
       ;   A3 = A2
       ),
       location_style_char(X-Y, A3, C)
    ;  true
    ),
    render_commands(Cursor, T).

:- dynamic location_style_char_/3.

tui_init :-
    retractall(location_style_char_(_, _, _)).

location_style_char(X-Y, Style, C) :-
    location_style_char_(X-Y, Style, C), !.

location_style_char(X-Y, Style, C) :-
    retractall(location_style_char_(X-Y, _, _)),
    set_cursor(X, Y),
    ansi_format(Style, '~s', [C]),
    assertz(location_style_char_(X-Y, Style, C)),
   !.



                /*******************************
                *     UNICODE LINES/BOXES      *
                *******************************/

char_from_to_line(C, X1-Y, X2-Y, L) :- !,
    (  X1 > X2
    -> From = X2, To = X1
    ;  From = X1, To = X2
    ),
    findall((X-Y)-C, between(From, To, X), L).

char_from_to_line(C, X-Y1, X-Y2, L) :- !,
    (  Y1 > Y2
    -> From = Y2, To = Y1
    ;  From = Y1, To = Y2
    ),
    findall((X-Y)-C, between(From, To, Y), L).

:- discontiguous style_corner_char/3.
:- discontiguous style_horizontal/2.
:- discontiguous style_vertical/2.

style_corner_char(thick, tl, '\u250f').
style_corner_char(thick, bl, '\u2517').
style_corner_char(thick, tr, '\u2513').
style_corner_char(thick, br, '\u251b').
style_horizontal(thick, '\u2501').
style_vertical(thick, '\u2503').

style_corner_char(thin, tl, '\u250c').
style_corner_char(thin, bl, '\u2514').
style_corner_char(thin, tr, '\u2510').
style_corner_char(thin, br, '\u2518').
style_horizontal(thin, '\u2500').
style_vertical(thin, '\u2502').


style_corner_char(double, tl, '\u2554').
style_corner_char(double, tr, '\u2557').
style_corner_char(double, bl, '\u255a').
style_corner_char(double, br, '\u255d').
style_horizontal(double, '\u2550').
style_vertical(double, '\u2551').


                /*******************************
                *     ALIASES (COMPONENTS)     *
                *******************************/

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
    char_from_to_line(Hoz, 1-0, WM-0, Top),
    char_from_to_line(Hoz, 1-H, WM-H, Bottom),
    char_from_to_line(Vrt, 0-1, 0-HM, Left),
    char_from_to_line(Vrt, W-1, W-HM, Right).


alias_drawable(clear(W-H), style([reset, bg(default)], Spaces)) :-
    findall((X-Y)-' ',
            ( between(0, W, X),
              between(0, H, Y) ),
            Spaces).

codes_value(I, V) :-
    escape_codes_value(I, V).

escape_codes_value([27, 91  |Codes], V) :-
    atom_codes(Atom, Codes),
    once(escaped_atom_value(Atom, V)).

escaped_atom_value('1~', home).
escaped_atom_value('2~', insert).
escaped_atom_value('3~', delete).
escaped_atom_value('4~', end).
escaped_atom_value('5~', page_up).
escaped_atom_value('6~', page_down).
escaped_atom_value('A', up).
escaped_atom_value('B', down).
escaped_atom_value('C', right).
escaped_atom_value('D', left).
escaped_atom_value('F', end).
escaped_atom_value('H', home).
escaped_atom_value('OP', f1).
escaped_atom_value('OQ', f2).
escaped_atom_value('OR', f3).
escaped_atom_value('OS', f4).
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

code_cntrl(1, start_of_heading).
code_cntrl(2, start_of_text).
code_cntrl(3, interrupt).
code_cntrl(4, eof).
code_cntrl(5, enquiry).
code_cntrl(6, acknowledge).
code_cntrl(7, bell).
code_cntrl(8, backspace).
code_cntrl(9, tab).
code_cntrl(10, linefeed).
code_cntrl(11, vertical_tab).
code_cntrl(12, formfeed).
code_cntrl(13, return).
code_cntrl(24, cancel).
code_cntrl(14, shift_out).
code_cntrl(15, shift_in).
code_cntrl(19, device_control_3).
code_cntrl(20, device_control_4).
code_cntrl(27, escape).
code_cntrl(127, delete).

code_value(C, V) :- code_cntrl(C, V).

code_value(C, V) :-
    \+ code_type(C, cntrl),
    char_code(V, C).

code_value(C, V) :-
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

direction(E) :- member(E, [up, down, left, right]).



wait_for_input :-
    get_single_input(_).

:- dynamic(last_tick/1).
input_or_tick(E) :-
    ( last_tick(Last), ! ; Last = 0 ),
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

       ;  read_escseq([ 27  |T ]-T, I)
       -> true
    )
    ), !.


read_escseq(L-T, Code) :-
    get_code(C),
    ( T = [C], codes_value(L, Code)
    -> true
    ;  wait_for_input([user_input], [user_input], -1)
    -> T = [C  |T2],
       read_escseq(L-T2, Code)
    ;  T = [],
       Code = L
    ).

stack_event_is(V, _, _) :- var(V), domain_error(stack_event_is, stack:V).

stack_event_is(_, V, _) :- var(V), domain_error(stack_event_is, event:V).

stack_event_is([H|T], E, Is) :-
    (  tui:at_event_is(H, E, Next)
    -> stack_event_is([H|T], Next, Is)
    ;  stack_event_is(T, E, Is)
    ), !.

stack_event_is([], E, Is) :-
    (  tui:at_event_is([], E, Next)
    -> stack_event_is([], Next, Is)
    ;  Is = E
    ), !.

