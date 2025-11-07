:- module(components, []).

:- reexport(tui).

tui:tui_module(components).

:- public(alias_drawable/2).
:- discontiguous(alias_drawable/2).

:- public(at_event_is/3).
:- discontiguous(at_event_is/3).


:- op(601, xfy, '.>').
:- op(601, xfy, '.\\/').
:- op(602, yfx, ~>).
:- op(602, fy, ~>).

alias_drawable(column([H]), H) :- !.

alias_drawable(column([]), []) :- !.

alias_drawable(column([H|T]), (H .\/ CT)) :- !,
    alias_drawable(column(T), CT).



alias_drawable(check_box(Title, Bool), CheckWithHover) :-
    (  Bool = true
    -> Check = style([     ], ('[x]' .> ': ' .> Title))
    ;  Check = style([faint], ('[ ]' .> ': ' .> Title))
    ),
    CheckWithHover = hover([underline], Check).

not(true, false).
not(false, true).

at_event_is(check_box(_Title, Bool), ' ', check_box-T) :- not(Bool, T).
at_event_is(check_box(_Title, Bool), return, check_box-T) :- not(Bool, T).


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


alias_drawable(frame(W-H, Contents), frame(W-H, Contents, _)).

alias_drawable(frame(W-H, Contents, Extent), [Clear, Box, Port]) :-
    (  W > 1, H > 1
    -> true
    ;  domain_error(valid_window_size, W-H)
    ),
    Box = box(W-H, thin),
    PW is W - 2,
    PH is H - 2,
    Clear = 1-1-clear(PW-PH),
    Port =  1-1-port(PW-PH, Contents, Extent).


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

title_l('\u2574').
title_r('\u2576').

alias_drawable(titled_frame(W-H, Title, Contents), titled_frame(W-H, Title, Contents, _)).

alias_drawable(titled_frame(W-H, Title, Contents, Extent), [FramePart, 1-0-TitlePart]) :-
    title_l(TL),
    title_r(TR),
    FramePart = frame(W-H, Contents, Extent),
    string_length(Title, TitleLength),
    MaxTitleLength is W - 2,
    (  TitleLength > MaxTitleLength
    -> string_length_adjusted(Title, MaxTitleLength, TitleText),
       TitlePart = TL .> style([bold], TitleText) .> TR
    ;  TitlePart = TL .> style([bold], Title) .> TR
    ).

overlap(A-B, C-D, O) :-
    B < A, !,
    overlap(B-A, C-D, O).

overlap(A-B, C-D, O) :-
    D < C, !,
    overlap(A-B, D-C, O).

overlap(A-B, C-D, O) :-
    C < A, !,
    overlap(C-D, A-B, O).

overlap(_-B, C-D, O) :-
    (  C < B
    -> O is min(B-C, D-C)
    ;  O is 0
    ).

scroll_char(h, s, s, '\u2500').
scroll_char(h, f, f, '\u2501').
scroll_char(h, s, f, '\u257c').
scroll_char(h, f, s, '\u257e').

scroll_char(v, s, s, '\u2502').
scroll_char(v, f, f, '\u2503').
scroll_char(v, s, f, '\u257d').
scroll_char(v, f, s, '\u257f').

/*
scroll_char(h, s, s, ' ').
scroll_char(h, f, f, '\u2500').
scroll_char(h, s, f, '\u2576').
scroll_char(h, f, s, '\u2574').

scroll_char(v, s, s, ' ').
scroll_char(v, f, f, '\u2502').
scroll_char(v, s, f, '\u2577').
scroll_char(v, f, s, '\u2575').
*/


nofm_seg_style_drawable(M/M, _, _, []) :- !.
nofm_seg_style_drawable(N/M, P1-P2, S, [X-Y-H|T]) :-
    % 0-based cell spans from N - N + 1
    % if N+0   to N+0.5 OVERLAPS seg, it's indicated
    % if N+0.5 to N+1   OVARLAPS seg, THAT part is indicated
    N0 is N/M,
    Np5 is (N + 0.5)/M,
    N1 is (N + 1)/M,
    (  overlap(N0-Np5, P1-P2, O1), O1 > 0
    -> A = f
    ;  A = s
    ),
    (  overlap(Np5-N1, P1-P2, O2), O2 > 0
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

portd_contentd_contento_style_drawable(PD, CD, _, S, D) :-
    PD >= CD, !,
    nofm_seg_style_drawable(0/PD, (-1)-(-1), S, D).

portd_contentd_contento_style_drawable(PD, CD, CO, S, D) :-
    (P1 is (-CO)/CD),
    (P2 is P1 + PD/CD),
    nofm_seg_style_drawable(0/PD, P1-P2, S, D).


alias_drawable(scroll(W-H, X-Y, Content),
                   [FramePart,
                    hscroll(1-HM1-HScroll, MaxScrollH),
                    vscroll(WM1-1-VScroll, MaxScrollV)
                   ]) :-
    HM1 is H - 1,
    WM1 is W - 1,

    drawable_raw(frame(W-H, X-Y-Content, EX-EY), FramePart),

    CW is EX - X + 1,
    CH is EY - Y + 1,

    PH is H - 2,
    PW is W - 2,

    MaxScrollH is CW - W + 1,
    MaxScrollV is CH - H + 1,

    portd_contentd_contento_style_drawable(PW, CW, X, h, HScroll),
    portd_contentd_contento_style_drawable(PH, CH, Y, v, VScroll).

alias_drawable(vscroll(C, _), C).
alias_drawable(hscroll(C, _), C).

at_event_is(vscroll(_, Max), up, scroll_up(Max)).
at_event_is(vscroll(_, Max), down, scroll_down(Max)).

at_event_is(hscroll(_, Max), right, scroll_right(Max)).
at_event_is(hscroll(_, Max), left, scroll_left(Max)).

at_event_is(scroll(_-_, X-Y, _), ScrollD, scroll-(X1-Y1)) :-
    ( ScrollD = scroll_down(Max),
      Y1 is max(Y - 1, -Max),
      X1 = X
    ; ScrollD = scroll_up(_),
      Y1 is min(0, Y + 1),
      X1 = X
    ; ScrollD = scroll_right(Max),
      X1 is max(X - 1, -Max),
      Y1 is Y
    ; ScrollD = scroll_left(_),
      X1 is min(0, X + 1),
      Y1 is Y
    ), !.
