:- module(tui_components, []).

/** <module> Ready-made TUI components

Styled components defined via the tui:alias_drawable/2 and
tui:at_event_is/3 hooks. Opt-in: load library(tui/components) to use
them. The unstyled building blocks they are made of (layout, shapes,
tagging, cursor) are core, in library(tui/drawable).
*/

:- use_module(library(tui)).

:- op(601, xfy, '.>').
:- op(601, xfy, '.\\/').

:- multifile tui:alias_drawable/2.
:- multifile tui:at_event_is/3.
:- discontiguous tui:alias_drawable/2.
:- discontiguous tui:at_event_is/3.


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

title_l('╴').
title_r('╶').


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

    % The content's size: inside the frame its port starts at 1-1, and
    % the content is offset from there by X-Y.
    CW is EX - X,
    CH is EY - Y,

    PH is H - 2,
    PW is W - 2,

    MaxScrollH is CW - PW,
    MaxScrollV is CH - PH,

    port_content_offset_axis_scrollbar(PW, CW, X, h, HScroll),
    port_content_offset_axis_scrollbar(PH, CH, Y, v, VScroll).

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

% Scroll indicator characters: each cell shows two halves, thin (s) or
% thick (f), so the thumb has half-cell resolution.

scroll_char(h, s, s, '─').
scroll_char(h, f, f, '━').
scroll_char(h, s, f, '╼').
scroll_char(h, f, s, '╾').

scroll_char(v, s, s, '│').
scroll_char(v, f, f, '┃').
scroll_char(v, s, f, '╽').
scroll_char(v, f, s, '╿').

% The scrollbar along axis S (h or v) for a port PD cells long, showing
% content CD long scrolled to offset CO (0 or negative). The track is PD
% cells of two halves each. The thumb's length, in whole halves, depends
% only on PD and CD, and its start moves with the offset, from the first
% half at offset 0 to the last at the largest offset. Fixing the length
% first keeps it from changing as the thumb moves. If the content fits,
% there is no thumb.
port_content_offset_axis_scrollbar(PD, CD, CO, S, D) :-
    Halves is 2 * PD,
    (   PD >= CD
    ->  Start = 0,
        Len = 0
    ;   Len is max(1, round(Halves * PD / CD)),
        Travel is Halves - Len,
        Start is max(0, min(Travel, round(Travel * -CO / (CD - PD))))
    ),
    End is Start + Len,
    axis_thumb_cells_scrollbar(S, Start-End, 0, PD, D).

% Cells N up to M of the track, with the thumb covering halves Start up
% to (not including) End.
axis_thumb_cells_scrollbar(_, _, M, M, []) :- !.
axis_thumb_cells_scrollbar(S, Thumb, N, M, [X-Y-Char | Cells]) :-
    I is 2 * N,
    J is I + 1,
    thumb_half_weight(Thumb, I, A),
    thumb_half_weight(Thumb, J, B),
    scroll_char(S, A, B, Char),
    (   S = h
    ->  X = N, Y = 0
    ;   X = 0, Y = N
    ),
    N1 is N + 1,
    axis_thumb_cells_scrollbar(S, Thumb, N1, M, Cells).

% Half I is thick (f) inside the thumb, thin (s) outside it.
thumb_half_weight(Start-End, I, W) :-
    (   I >= Start,
        I < End
    ->  W = f
    ;   W = s
    ).
