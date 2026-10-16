:- module(tui_components, []).

/** <module> Reusable TUI components

Standard components defined via tui:alias_drawable/2 and
tui:at_event_is/3 multifile hooks. Auto-loaded by library(tui).
*/

:- use_module(library(tui)).

:- op(601, xfy, '.>').
:- op(601, xfy, '.\\/').

:- multifile tui:alias_drawable/2.
:- multifile tui:at_event_is/3.
:- discontiguous tui:alias_drawable/2.
:- discontiguous tui:at_event_is/3.


'#tagging'.

%!  Key:Drawable — annotation operator.
%
%  Attaches a tag to a drawable. The left-hand side is ignored for
%  rendering — Drawable is drawn as-is.
%
%  For event bubbling: when a component event (ComponentName-Value)
%  passes through a Key:Component node, and ComponentName matches
%  the functor of Component, the event is rewritten to Key-Value.
%  This replaces the component's own name with the tag, namespacing
%  the event for routing.
%
%  Events from deeper nested components (whose functor doesn't match)
%  pass through unmodified. Raw events (atoms, non-pair terms) also
%  pass through — they are not component events.
%
%  Example:
%    scroll(Id) : scroll(20-15, Offset, Content)
%    %% scroll fires scroll-(0-5), tag rewrites to scroll(1)-(0-5)
%
tui:alias_drawable(_:D, D).
tui:at_event_is(Key:Inner, ComponentKey-Value, Key-Value) :-
    functor(Inner, ComponentKey, _).


'#shapes'.

%!  box(+W-+H, +Style)
%
%  A W×H box border in the given Style (thin, thick, or double).
%  The box is hollow — only the border characters are drawn.
tui:alias_drawable(box(W0-H0, Style), [Top, Bottom, Left, Right, Corners]) :-
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
    Top    = line(Hoz, 1-0, WM-0),
    Bottom = line(Hoz, 1-H, WM-H),
    Left   = line(Vrt, 0-1, 0-HM),
    Right  = line(Vrt, W-1, W-HM).

%!  clear(+W-+H)
%
%  A W×H rectangle of spaces with reset styling. Used to erase a
%  region before drawing over it.
tui:alias_drawable(clear(W-H), style([reset, bg(default)], Spaces)) :-
    findall((X-Y)-' ',
            ( between(0, W, X),
              between(0, H, Y) ),
            Spaces).

tui:alias_drawable(line(Char, From, To), Line) :-
    char_from_to_line(Char, From, To, Line).

at_towards_next(At, Towards, Next) :-
    (   At < Towards
    ->  Next is At + 1
    ;   At > Towards
    ->  Next is At - 1
    ;   fail
    ).  
% Line and box-drawing character tables.

char_from_to_line(C, X-Y, X-Y, [X-Y-C]) :- !.

char_from_to_line(C, X1-Y, X2-Y, [X1-Y-C | Tail]) :- !,
    at_towards_next(X1, X2, Next),
    char_from_to_line(C, Next-Y, X2-Y, Tail).

char_from_to_line(C, X-Y1, X-Y2, [X-Y1-C | Tail]) :- !,
    at_towards_next(Y1, Y2, Next),
    char_from_to_line(C, X-Next, X-Y2, Tail).
    
:- discontiguous style_corner_char/3.
:- discontiguous style_horizontal/2.
:- discontiguous style_vertical/2.

style_corner_char(thick, tl, '┏').
style_corner_char(thick, bl, '┗').
style_corner_char(thick, tr, '┓').
style_corner_char(thick, br, '┛').
style_horizontal(thick, '━').
style_vertical(thick, '┃').

style_corner_char(thin, tl, '┌').
style_corner_char(thin, bl, '└').
style_corner_char(thin, tr, '┐').
style_corner_char(thin, br, '┘').
style_horizontal(thin, '─').
style_vertical(thin, '│').

style_corner_char(double, tl, '╔').
style_corner_char(double, tr, '╗').
style_corner_char(double, bl, '╚').
style_corner_char(double, br, '╝').
style_horizontal(double, '═').
style_vertical(double, '║').


'#layout'.

%!  column(+Drawables)
%
%  Vertically stack a list of drawables using .\/ (top to bottom).
tui:alias_drawable(column([H]), H) :- !.
tui:alias_drawable(column([]), []) :- !.
tui:alias_drawable(column([H|T]), (H .\/ column(T))) :- !.

%!  row(+Drawables)
%
%  Horizontally concatenate a list of drawables using .> (left to right).
tui:alias_drawable(row([H]), H) :- !.
tui:alias_drawable(row([]), []) :- !.
tui:alias_drawable(row([H|T]), (H .> row(T))) :- !.

%!  wrapped(+Width, +Chars)
%
%  Chars broken into rows of Width characters, top to bottom. N chars
%  take N // Width + 1 rows, so the position just after the last char
%  always lies on a row (the last row may be empty).
tui:alias_drawable(wrapped(W, Chars), column(Rows)) :-
    width_chars_rows(W, Chars, Rows).

width_chars_rows(W, Chars, [chars(Row) | Rows]) :-
    (   length(Row, W),
        append(Row, Rest, Chars)
    ->  width_chars_rows(W, Rest, Rows)
    ;   Row = Chars,
        Rows = []
    ).


'#input_controls'.

%!  check_box(+Title, +Bool)
%
%  A toggleable checkbox. Displays [x] or [ ] followed by Title.
%  Highlighted with underline on hover. Faint when unchecked.
%
%  Events produced:
%    * check_box-NewBool on space or return (toggles Bool)
tui:alias_drawable(check_box(Title, Bool), CheckWithHover) :-
    (  Bool = true
    -> Check = style([     ], ('[x]' .> ': ' .> Title))
    ;  Check = style([faint], ('[ ]' .> ': ' .> Title))
    ),
    CheckWithHover = hover([underline], Check).

not(true, false).
not(false, true).

tui:at_event_is(check_box(_Title, Bool), ' ', check_box-T) :- not(Bool, T).
tui:at_event_is(check_box(_Title, Bool), return, check_box-T) :- not(Bool, T).

%!  input(+Width, +Placeholder, ?Value)
%
%  A text input field of fixed Width. When Value is unbound, displays
%  the Placeholder in faint underlined style. When bound, displays the
%  value underlined.
tui:alias_drawable(input(W, PlaceholderA, ValueA), D) :-
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


'#containers'.

%!  frame(+W-+H, +Contents)
%!  frame(+W-+H, +Contents, -Extent)
%
%  A thin-bordered box of size W×H containing Contents in a viewport.
%  The interior is cleared before rendering. Extent is unified with
%  the MaxX-MaxY of the content (useful for scrolling).
tui:alias_drawable(frame(W-H, Contents), frame(W-H, Contents, _)).
tui:alias_drawable(frame(W-H, Contents, Extent), [Clear, Box, Port]) :-
    (  W > 1, H > 1
    -> true
    ;  domain_error(valid_window_size, W-H)
    ),
    Box = box(W-H, thin),
    PW is W - 2,
    PH is H - 2,
    Clear = 1-1-clear(PW-PH),
    Port =  1-1-port(PW-PH, Contents, Extent).

%!  titled_frame(+W-+H, +Title, +Contents)
%!  titled_frame(+W-+H, +Title, +Contents, -Extent)
%
%  A frame with a bold Title rendered in the top border. Title is
%  truncated if it exceeds the frame width.
tui:alias_drawable(titled_frame(W-H, Title, Contents), titled_frame(W-H, Title, Contents, _)).
tui:alias_drawable(titled_frame(W-H, Title, Contents, Extent), [FramePart, 1-0-TitlePart]) :-
    title_l(TL),
    title_r(TR),
    FramePart = frame(W-H, Contents, Extent),
    MaxTitleLength is W - 2,
    TitlePart = [TL .> port(MaxTitleLength-1, Title .> TR) ].
    
    % string_length(Title, TitleLength),
    % (  TitleLength > MaxTitleLength
    % -> string_length_adjusted(Title, MaxTitleLength, TitleText),
    %    TitlePart = TL .> style([bold], TitleText) .> TR
    % ;  TitlePart = TL .> style([bold], Title) .> TR
    % ).

title_l('\u2574').
title_r('\u2576').


'#scrolling'.

%!  scroll(+W-+H, +ScrollX-+ScrollY, +Content)
%
%  A scrollable frame. Content is rendered inside a W×H bordered
%  viewport offset by ScrollX-ScrollY. Scroll indicators appear on
%  the bottom and right edges using half-block line-drawing characters.
%
%  Events produced:
%    * scroll-(NewX-NewY) on arrow keys when cursor is on a scrollbar
tui:alias_drawable(scroll(W-H, X-Y, Content),
                   [FramePart,
                    hscroll(1-HM1-HScroll, MaxScrollH),
                    vscroll(WM1-1-VScroll, MaxScrollV)
                   ]) :-
    HM1 is H - 1,
    WM1 is W - 1,

    drawable_raw(frame(W-H, X-Y-scrollable(Content, MaxScrollH, MaxScrollV), EX-EY), FramePart),

    CW is EX - X + 1,
    CH is EY - Y + 1,

    PH is H - 2,
    PW is W - 2,

    MaxScrollH is CW - W + 1,
    MaxScrollV is CH - H + 1,

    portd_contentd_contento_style_drawable(PW, CW, X, h, HScroll),
    portd_contentd_contento_style_drawable(PH, CH, Y, v, VScroll).

tui:alias_drawable(scrollable(C, _, _), C).

tui:alias_drawable(vscroll(C, _), C).
tui:alias_drawable(hscroll(C, _), C).

tui:at_event_is(frame(_-H, X-Y-scrollable(_, _, _MaxV), _), page_up, scroll-(X-Y1)) :-
    Delta is (H - 2 - 1),
    Y1 is min(0, Y + Delta).
    
tui:at_event_is(frame(_-H, X-Y-scrollable(_, _, MaxV), _), page_down, scroll-(X-Y1)) :-
    Delta is (H - 2 - 1),
    Y1 is max(Y - Delta, -MaxV).

tui:at_event_is(vscroll(_, Max), up, scroll_up(Max)).
tui:at_event_is(vscroll(_, Max), down, scroll_down(Max)).

tui:at_event_is(hscroll(_, Max), right, scroll_right(Max)).
tui:at_event_is(hscroll(_, Max), left, scroll_left(Max)).

tui:at_event_is(scroll(_-_, X-Y, _), ScrollD, scroll-(X1-Y1)) :-
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


'#helpers'.

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

% Scroll indicator characters — half-block line drawing for
% sub-cell-resolution scroll position display.

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
