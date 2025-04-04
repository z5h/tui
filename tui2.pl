:- module(tui2,
          [ render/2,
            op(601, xfy, '.>'),
            op(601, xfy, '.\\/')
          ]).

:- use_module(local(core/core)).
:- use_module(library(ansi_term)).
:- use_module(library(ansi_termx)).


:- op(601, xfy, '.>').
:- op(601, xfy, '.\\/').


                /*******************************
                *          UTILITIES           *
                *******************************/


my_clear_screen :-
    set_cursor(1,1),
    format('\e[0J').

set_cursor(X,Y) :-
    format('\e[~d;~dH',[Y,X]).

is_attribute(A) :-
    member(A, [reset,
               bold,
               italic,
               underline,
               negative,
               bold,
               faint,
               crossed_out]).

is_attribute(A) :-
    ( A = fg(Color)
    ; A = bg(Color)
    ; A = hbg(Color)
    ; A = hfg(Color)
    ), my_color(Color).

is_attribute(id(_)).

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
command((X-Y)-(Attrs-C)) :-
    integer(X),
    integer(Y),
    is_list(Attrs),
    maplist(is_attribute, Attrs),
    atom(C),
    atom_length(C, 1).


%!  commands_end(+Commands, -End)
%
%   End = X-Y where
%   X is the max X found in Commands, and
%   Y is the max Y found in Commands.
commands_end((X-Y)-(_-_), X-Y).
commands_end([], 0-0).
commands_end([H|T], X3-Y3) :-
    @ commands_end(H, X1-Y1),
    @ commands_end(T, X2-Y2),
    Y3 is max(Y1, Y2),
    X3 is max(X1, X2).


%!  translate_command_translated(+Delta, +C0, -C1).
%
%   Translates a drawing command by Delta in the form of DX-DY.
translate_command_translated(DX-DY, (X-Y)-(Attr-C), (X1-Y1)-(Attr-C)) :-
    X1 is X + DX,
    Y1 is Y + DY.

%!  attrs_command_styled(+AttrsOuter, +C0, -C1).
%
%   Calculates the result of C0s attributes in the context of
%   surrounding attributes AttrsOuter, and stores the result in
%   the attributes of C1.
attrs_command_styled(AttrsOuter, (X-Y)-(AttrInner-C), (X-Y)-(AttrResult-C)) :-
    attrs_old_new(AttrInner, AttrsOuter, AttrResult).

attrs_old_new([], A, A).
attrs_old_new([H|T], O, N) :-
    assertion(is_attribute(H)),
    attr_old_new(H, O, N1),
    attrs_old_new(T, N1, N).

attr_old_new(reset, _, [reset]) :- !.

attr_old_new(-A, Old, New) :- !,
    exclude(=(A), Old, New).

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


%!  port_visible(+Bounds, +Command).
%
%   True if the Command is for a location within the W-H Boundaries.
port_visible(W-H, (X-Y)-(_-_)) :-
    X > -1, X < W,
    Y > -1, Y < H.

:- meta_predicate mapnestedlist(2, ?, ?).
mapnestedlist(F, [H|T], [FH|FT]) :- !,
    mapnestedlist(F, H,FH),
    mapnestedlist(F, T,FT).

mapnestedlist(_, [], []) :- !.
mapnestedlist(F, D, FD) :-
    call(F,D,FD).


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
drawable_command([H|T], [CH|CT]) :- !,
    drawable_command(H,CH),
    drawable_command(T, CT).

drawable_command([], []) :- !.

drawable_command((X-Y)-A, Command) :-
    ( atom(A), atom_chars(A, Chars)
    ; string(A), string_chars(A, Chars)
    ; number(A), number_chars(A, Chars)
    ), !,
    sequence_at_command(Chars, X-Y, Command).

drawable_command(A, Command) :-
    ( atom(A), atom_chars(A, Chars)
    ; string(A), string_chars(A, Chars)
    ; number(A), number_chars(A, Chars)
    ), !,
    sequence_at_command(Chars, 0-0, Command).

drawable_command(raw(C), C) :- !.

sequence_at_command([], _, []).
sequence_at_command([C|R], X-Y, [(X-Y)-([]-C)|SR]) :-
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

drawable_command(A, C) :-
    alias_drawable(A, D), !,
    @ drawable_command(D, C).


drawable_command(D, _) :-
    $$$ bad:D.
                /*******************************
                *            RENDER            *
                *******************************/


render_commands(Drawables, Deduped) :-
    drawable_command(translate(1-1, Drawables), Commands),
    keylist_deduped_prioritize_last(Commands, Deduped).

render(Drawables, EventMap) :-
    cursor_save,
    render_commands(Drawables, Commands),
    commands_end(Commands, X-Y),
    % my_clear_screen,
    render_commands_eventmap(Commands, EventMap), !,
    cursor_unsave.

onscreen(X-Y) :-
    X > 0,
    Y > 0.

better_delete(L0, E, L1) :-
    append([Pre, [E], Post], L0),
    append(Pre, Post, L1), !.

render_commands_eventmap([], []).
render_commands_eventmap([((X-Y)-(A-C))|T], EM) :-
    (  onscreen(X-Y)
    -> set_cursor(X, Y),
       reverse(A, RA),
       (  better_delete(RA, id(ID), RA1)
       -> ansi_format(RA1,'~s', [C]),
          EM = [(X-Y)-ID | EMT ]

       ;  ansi_format(RA,'~s', [C]),
          EM = EMT
       )
    ; EM = EMT
    ),
    render_commands_eventmap(T, EMT).



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


:- discontiguous(alias_drawable/2).
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


alias_drawable(frame(W-H, Style, Contents), [Clear, Box, Port]) :-
  Box = box(W-H, Style),
  PW is W - 2,
  PH is H - 2,
  Clear = 1-1-clear(PW-PH),
  Port =  1-1-port(PW-PH, Contents).

alias_drawable(frame(W-H, Style, Title, Contents), [FramePart, 1-0-TitlePart]) :-
    FramePart = frame(W-H, Style, Contents),
    string_length(Title, TitleLength),
    MaxTitleLength is W - 2,
    (  TitleLength > MaxTitleLength
    -> string_length_adjusted(Title, MaxTitleLength, TitleText),
       TitlePart = style([bold], TitleText)
    ;  TitlePart = style([bold], Title)
    ).

portd_contentd_contento_style_drawable(PD, CD, _, S, D) :-
    PD >= CD, !,
    nofm_seg_style_drawable(0/PD, (-1)-(-1), S, D).

portd_contentd_contento_style_drawable(PD, CD, CO, S, D) :-
    @ (P1 is abs(CO)/CD),
    @ (P2 is P1 + PD/CD),
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
    commands_end(CC, CW-CH),
    FramePart = frame(W-H, thin, X-Y-raw(CC)),
    PH is H - 2,
    PW is W - 2,
    @ portd_contentd_contento_style_drawable(PW, CW, X, h, HScroll),
    @ portd_contentd_contento_style_drawable(PH, CH, Y, v, VScroll).


alias_drawable(clear(W-H), style([reset], Spaces)) :-
    findall((X-Y)-' ',
            ( between(0, W, X),
              between(0,H,Y)),
            Spaces).

alias_drawable(Id:Drawable, style([id(Id)], Drawable)).

alias_drawable(A .> B, Drawable) :-
    drawable_command(A, AC),
    commands_end(AC, X-_Y),
    X1 is X + 1,
    Drawable = [raw(AC), translate(X1-0, B)].

alias_drawable(A .\/ B, Drawable) :-
    drawable_command(A, AC),
    commands_end(AC, _X-Y),
    Y1 is Y + 1,
    Drawable = [raw(AC), translate(0-Y1, B)].


init(M) :-
    list_to_assoc(
        [content-abcdefghijklmnopqrtuvwxyz,
         offset-(0-0)
        ],
        M).

view(M, V) :-
    get_assoc(content, M, Content),
    get_assoc(offset, M, Offset),
    V = s1:scroll(10-3, Offset-Content).

update(s1:D, M0, M1) :-
    get_assoc(content, M0, Content),
    render_commands(Content, Commands),
    commands_end(Commands, XE-YE),

    ( D = backward, DX-DY = (-1)-0
    ; D = forward,  DX-DY  = 1-0
    ; D = up,       DX-DY  = 0-(-1)
    ; D = down,     DX-DY  = 0-1
    ),
    get_assoc(offset, M0, X-Y),
    X1 is X + DX,
    Y1 is Y + DY,
    X1 =< 0,
    Y1 =< 0,
    put_assoc(offset, M0, X1-Y1, M1), !.

update(s1:_, M, M).

q(113).
c(99).

dir([27, 91, 65], up).
dir([27, 91, 66], down).
dir([27, 91, 67], forward).
dir([27, 91, 68], backward).

is_dir(up).
is_dir(down).
is_dir(forward).
is_dir(backward).

loop(M) :-
    view(M, V),
    render(V, EM),
    list_to_assoc(EM, AEM),

    cursor_position(YY,XX),

    get_single_input(C),


    (  (get_assoc(XX-YY, AEM, ID), update(ID:C, M, M1))
    -> loop(M1)

    ;  is_dir(C)
    -> cursor_move(1, C),!,
       loop(M)

    ;  q(C)
    -> false

    ;  loop(M)
    ).

get_single_input(I) :-
    with_tty_raw(read_input_raw(Codes, infinite)),
    (  dir(Codes, I)
    -> true
    ;  Codes = [I]
    ).

read_input_raw(Codes, T) :-
    wait_for_input([user_input], Ready, T),
    (  Ready = [user_input]
    -> get_single_char(C),
       Codes = [C | Rest],
       read_input_raw(Rest, -1)

    ;  Codes = []
    ).

go :-
    with_tty_raw(
        ( clear_screen,
          init(M),
          loop(M)
        )).
