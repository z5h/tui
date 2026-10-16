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

tui:at_event_is(check_box(_Title, Bool), _-' ', check_box-T) :- not(Bool, T).
tui:at_event_is(check_box(_Title, Bool), _-return, check_box-T) :- not(Bool, T).

%!  input(+Width, +Placeholder, ?Value)
%
%  A one-line text field Width wide, after a faint '> ', bold with the
%  cursor on it. Shows Value underlined, or while Value is unbound, the
%  Placeholder faint and underlined. Text beyond Width is not shown.
%
%  With the cursor in the field: typing inserts at the cursor (at the end
%  of the text, if the cursor is past it) and advances it, backspace
%  deletes before the cursor, delete deletes at it, and a paste is
%  inserted, its line breaks as spaces.
%
%  Events produced:
%    * input-NewValue, a string, followed by the moves (right or left)
%      that keep the cursor after the edit
tui:alias_drawable(input(W, PlaceholderA, ValueA), hover([bold], D)) :-
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

tui:at_event_is(input(_, _, ValueA), (X-_)-E, Is) :-
    I0 is X - 2,
    I0 >= 0,
    (   var(ValueA)
    ->  Value = ""
    ;   atomics_to_string([ValueA], Value)
    ),
    string_length(Value, L),
    I is min(I0, L),
    event_index_value_edited(E, I, Value, Edited, Moves),
    (   Is = input-Edited
    ;   member(Is, Moves)
    ).

% Value with E applied at index I, and the cursor moves that follow.
event_index_value_edited(paste(Text), I, Value, Edited, Moves) :- !,
    split_string(Text, "\n", "", Lines),
    atomic_list_concat(Lines, ' ', Inserted),
    string_index_inserted_edited(Inserted, I, Value, Edited),
    atom_length(Inserted, N),
    length(Moves, N),
    maplist(=(right), Moves).
event_index_value_edited(backspace, I, Value, Edited, [left]) :- !,
    I > 0,
    sub_string(Value, 0, I, _, Before0),
    sub_string(Before0, 0, _, 1, Before),
    sub_string(Value, I, _, 0, After),
    string_concat(Before, After, Edited).
event_index_value_edited(delete, I, Value, Edited, []) :- !,
    sub_string(Value, 0, I, _, Before),
    sub_string(Value, I, _, 0, After0),
    sub_string(After0, 1, _, 0, After),
    string_concat(Before, After, Edited).
event_index_value_edited(C, I, Value, Edited, [right]) :-
    atom(C),
    atom_length(C, 1),
    char_code(C, Code),
    Code >= 32,
    Code =\= 127,
    string_index_inserted_edited(C, I, Value, Edited).

string_index_inserted_edited(S, I, Value, Edited) :-
    sub_string(Value, 0, I, _, Before),
    sub_string(Value, I, _, 0, After),
    atomics_to_string([Before, S, After], Edited).


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
%  viewport offset by ScrollX-ScrollY (0 or negative). On each axis where
%  the content does not fit, a scrollbar replaces that edge of the border
%  (bottom for horizontal, right for vertical), drawn with half-cell
%  resolution.
%
%  Shift+arrows drag what is under the cursor, as with a mouse:
%
%    * anywhere in the frame, the content, one row or column per press
%    * on a scrollbar, along its axis, the thumb, one half-cell per press
%
%  Page up and page down move by a page, anywhere in the frame.
%
%  Events produced:
%    * scroll-(NewX-NewY), the new offset
tui:alias_drawable(scroll(W-H, X-Y, Content), scroll_view(X-Y, MaxH-MaxV, PH, [FramePart | Bars])) :-
    HM1 is H - 1,
    WM1 is W - 1,

    drawable_raw(frame(W-H, X-Y-Content, EX-EY), FramePart),

    % The content's size: inside the frame its port starts at 1-1, and
    % the content is offset from there by X-Y.
    CW is EX - X,
    CH is EY - Y,

    PH is H - 2,
    PW is W - 2,

    MaxH is max(0, CW - PW),
    MaxV is max(0, CH - PH),

    (   CW > PW
    ->  port_content_offset_axis_scrollbar(PW, CW, X, h, HScroll),
        port_content_step(PW, CW, StepH),
        HBars = [hscroll(1-HM1-HScroll, StepH)]
    ;   HBars = []
    ),
    (   CH > PH
    ->  port_content_offset_axis_scrollbar(PH, CH, Y, v, VScroll),
        port_content_step(PH, CH, StepV),
        VBars = [vscroll(WM1-1-VScroll, StepV)]
    ;   VBars = []
    ),
    append(HBars, VBars, Bars).

% scroll_view(Offset, Limits, PageHeight, Drawable): a scroll's frame and
% bars, carrying what its events need.
tui:alias_drawable(scroll_view(_, _, _, D), D).

tui:alias_drawable(vscroll(D, _), D).
tui:alias_drawable(hscroll(D, _), D).

% On a scrollbar, Shift+arrows along its axis drag the thumb by Step.
tui:at_event_is(vscroll(_, Step), _-(shift+D), thumb_dragged(D, Step)) :-
    memberchk(D, [up, down]).
tui:at_event_is(hscroll(_, Step), _-(shift+D), thumb_dragged(D, Step)) :-
    memberchk(D, [left, right]).

tui:at_event_is(scroll_view(X-Y, MaxH-MaxV, PH, _), _-E, scroll-(X1-Y1)) :-
    page_event_shift(PH, E, DX-DY),
    X1 is max(-MaxH, min(0, X + DX)),
    Y1 is max(-MaxV, min(0, Y + DY)).

% How an event shifts the content, for a page PH rows high. Dragging the
% content moves it with the arrow; dragging the thumb moves the thumb
% with the arrow, so the content the other way.
page_event_shift(_, shift+up, 0-(-1)).
page_event_shift(_, shift+down, 0-1).
page_event_shift(_, shift+left, (-1)-0).
page_event_shift(_, shift+right, 1-0).
page_event_shift(_, thumb_dragged(up, S), 0-S).
page_event_shift(_, thumb_dragged(down, S), 0-DY) :-
    DY is -S.
page_event_shift(_, thumb_dragged(left, S), S-0).
page_event_shift(_, thumb_dragged(right, S), DX-0) :-
    DX is -S.
page_event_shift(PH, page_up, 0-Page) :-
    Page is max(1, PH - 1).
page_event_shift(PH, page_down, 0-DY) :-
    DY is -max(1, PH - 1).


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
% content CD long (CD > PD) scrolled to offset CO (0 or negative). Its
% thumb starts at the first half at offset 0, and at the last half the
% thumb can reach at the largest offset.
port_content_offset_axis_scrollbar(PD, CD, CO, S, D) :-
    port_content_thumb(PD, CD, Len, Travel),
    Start is max(0, min(Travel, round(Travel * -CO / (CD - PD)))),
    End is Start + Len,
    axis_thumb_cells_scrollbar(S, Start-End, 0, PD, D).

% The thumb for a port PD cells long showing content CD long (CD > PD):
% the track is PD cells of two halves each; the thumb is Len halves long,
% and its start can move Travel halves. The length depends only on PD and
% CD, so it does not change as the thumb moves.
port_content_thumb(PD, CD, Len, Travel) :-
    Halves is 2 * PD,
    Len is max(1, round(Halves * PD / CD)),
    Travel is Halves - Len.

% How far the content moves when the thumb is dragged one half: the
% scroll range over the thumb's travel, at least 1.
port_content_step(PD, CD, Step) :-
    port_content_thumb(PD, CD, _, Travel),
    Max is CD - PD,
    (   Travel > 0
    ->  Step is max(1, round(Max / Travel))
    ;   Step = Max
    ).

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
