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
%  A toggleable checkbox. Displays [x] or [ ] followed by Title, faint
%  when unchecked, bold with the cursor on it.
%
%  Events produced:
%    * check_box-NewBool on space, return or a left click (toggles Bool)
tui:alias_drawable(check_box(Title, Bool), hover([bold], Check)) :-
    (  Bool = true
    -> Check = style([     ], ('[x]' .> ': ' .> Title))
    ;  Check = style([faint], ('[ ]' .> ': ' .> Title))
    ).

not(true, false).
not(false, true).

tui:at_event_is(check_box(_Title, Bool), _-' ', check_box-T) :- not(Bool, T).
tui:at_event_is(check_box(_Title, Bool), _-return, check_box-T) :- not(Bool, T).
tui:at_event_is(check_box(_Title, Bool), _-mouse(press, left), check_box-T) :- not(Bool, T).

%!  button(+Label)
%
%  A button, shown as [ Label ], bold with the cursor on it.
%
%  Events produced:
%    * button-pressed on space, return or a left click
tui:alias_drawable(button(Label), hover([bold], '[ ' .> Label .> ' ]')).

tui:at_event_is(button(_), _-' ', button-pressed).
tui:at_event_is(button(_), _-return, button-pressed).
tui:at_event_is(button(_), _-mouse(press, left), button-pressed).

%!  input(+Width, +Placeholder, ?Value)
%
%  A one-line text field Width wide, after a faint '> ', bold with the
%  cursor on it. Shows Value underlined, or while Value is unbound, the
%  Placeholder faint and underlined. Text beyond Width is not shown.
%
%  The cursor stays where text can be edited: arriving by arrow or click
%  past the end of the text (trailing spaces are text; the padding to
%  Width is not), or on the '> ', it moves to the nearest such cell.
%
%  With the cursor in the field: typing inserts at the cursor (at the end
%  of the text, if the cursor is past it) and advances it, backspace
%  deletes before the cursor, delete deletes at it, and a paste is
%  inserted, its line breaks as spaces.
%
%  Events produced:
%    * input-NewValue, a string, followed by cursor_by(DX-0) if the
%      cursor must move to stay after the edit
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

% Arriving past the end of the text, or on the prompt, the cursor moves
% to the nearest cell where text can be edited.
tui:at_event_is(input(_, _, ValueA), (X-_)-E, cursor_by(DX-0)) :-
    arrival_event(E),
    value_string(ValueA, Value),
    string_length(Value, L),
    I is X - 2,
    (   I > L
    ->  DX is L - I
    ;   I < 0,
        DX is -I
    ).
tui:at_event_is(input(_, _, ValueA), (X-_)-E, Is) :-
    I0 is X - 2,
    I0 >= 0,
    value_string(ValueA, Value),
    string_length(Value, L),
    I is min(I0, L),
    event_index_value_edited(E, I, Value, Edited, I1),
    DX is I1 - I0,
    (   Edited == Value,
        DX =:= 0
    ->  Is = noop
    ;   (   Edited \== Value,
            Is = input-Edited
        ;   DX =\= 0,
            Is = cursor_by(DX-0)
        )
    ).

arrival_event(arrived(_)).
arrival_event(mouse(press, left)).

value_string(ValueA, Value) :-
    (   var(ValueA)
    ->  Value = ""
    ;   atomics_to_string([ValueA], Value)
    ).

% Value with E applied at index I, and the cursor's index after.
event_index_value_edited(paste(Text), I, Value, Edited, I1) :- !,
    split_string(Text, "\n", "", Lines),
    atomic_list_concat(Lines, ' ', Inserted),
    string_index_inserted_edited(Inserted, I, Value, Edited),
    atom_length(Inserted, N),
    I1 is I + N.
% Backspace at the start and delete at the end change nothing, but are
% still the field's (noop): they do not bubble on.
event_index_value_edited(backspace, I, Value, Edited, I1) :- !,
    (   I > 0
    ->  sub_string(Value, 0, I, _, Before0),
        sub_string(Before0, 0, _, 1, Before),
        sub_string(Value, I, _, 0, After),
        string_concat(Before, After, Edited),
        I1 is I - 1
    ;   Edited = Value,
        I1 = I
    ).
event_index_value_edited(delete, I, Value, Edited, I) :- !,
    (   string_length(Value, L),
        I < L
    ->  sub_string(Value, 0, I, _, Before),
        sub_string(Value, I, _, 0, After0),
        sub_string(After0, 1, _, 0, After),
        string_concat(Before, After, Edited)
    ;   Edited = Value
    ).
event_index_value_edited(C, I, Value, Edited, I1) :-
    atom(C),
    atom_length(C, 1),
    char_code(C, Code),
    Code >= 32,
    Code =\= 127,
    string_index_inserted_edited(C, I, Value, Edited),
    I1 is I + 1.

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
%  A frame with Title in its top border, cut off at the frame's edge.
%  Title is any drawable.
tui:alias_drawable(titled_frame(W-H, Title, Contents), titled_frame(W-H, Title, Contents, _)).
tui:alias_drawable(titled_frame(W-H, Title, Contents, Extent), [FramePart, 1-0-TitlePart]) :-
    title_l(TL),
    title_r(TR),
    FramePart = frame(W-H, Contents, Extent),
    MaxTitleLength is W - 2,
    TitlePart = port(MaxTitleLength-1, TL .> Title .> TR).

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
%  Page up and page down move by a page, anywhere in the frame. With the
%  mouse (see app/5), the wheel scrolls the content a row or column at a
%  time, and pressing or dragging the left button on a scrollbar moves
%  the thumb to the mouse.
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
        HBars = [1-HM1-hscroll(HScroll, StepH, PW-CW)]
    ;   HBars = []
    ),
    (   CH > PH
    ->  port_content_offset_axis_scrollbar(PH, CH, Y, v, VScroll),
        port_content_step(PH, CH, StepV),
        VBars = [WM1-1-vscroll(VScroll, StepV, PH-CH)]
    ;   VBars = []
    ),
    append(HBars, VBars, Bars).

% scroll_view(Offset, Limits, PageHeight, Drawable): a scroll's frame and
% bars, carrying what its events need.
tui:alias_drawable(scroll_view(_, _, _, D), D).

% vscroll(D, Step, PD-CD), hscroll(D, Step, PD-CD): a scrollbar, PD cells
% long from its origin, whose thumb moves the content Step per half-cell,
% for a port PD long showing content CD long.
tui:alias_drawable(vscroll(D, _, _), D).
tui:alias_drawable(hscroll(D, _, _), D).

% On a scrollbar, Shift+arrows along its axis drag the thumb by Step; the
% left button, pressed or dragged, moves the thumb to the mouse.
tui:at_event_is(vscroll(_, Step, _), _-(shift+D), thumb_dragged(D, Step)) :-
    memberchk(D, [up, down]).
tui:at_event_is(hscroll(_, Step, _), _-(shift+D), thumb_dragged(D, Step)) :-
    memberchk(D, [left, right]).
tui:at_event_is(vscroll(_, _, PD-CD), (_-N)-mouse(A, left), thumb_at(v, O)) :-
    memberchk(A, [press, drag]),
    port_content_cell_offset(PD, CD, N, O).
tui:at_event_is(hscroll(_, _, PD-CD), (N-_)-mouse(A, left), thumb_at(h, O)) :-
    memberchk(A, [press, drag]),
    port_content_cell_offset(PD, CD, N, O).

tui:at_event_is(scroll_view(X-_, _, _, _), _-thumb_at(v, O), scroll-(X-O)).
tui:at_event_is(scroll_view(_-Y, _, _, _), _-thumb_at(h, O), scroll-(O-Y)).
% At its limits the scroll still takes the event, to do nothing.
tui:at_event_is(scroll_view(X-Y, MaxH-MaxV, PH, _), _-E, Is) :-
    page_event_shift(PH, E, DX-DY),
    X1 is max(-MaxH, min(0, X + DX)),
    Y1 is max(-MaxV, min(0, Y + DY)),
    (   X1-Y1 == X-Y
    ->  Is = noop
    ;   Is = scroll-(X1-Y1)
    ).

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
page_event_shift(_, mouse(scroll, up), 0-1).
page_event_shift(_, mouse(scroll, down), 0-(-1)).
page_event_shift(_, mouse(scroll, left), 1-0).
page_event_shift(_, mouse(scroll, right), (-1)-0).
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

% The offset (0 or negative) for the mouse on cell N of the track: the
% first cell is the start of the content, the last its end, in
% proportion between.
port_content_cell_offset(PD, CD, N, O) :-
    (   PD > 1
    ->  N1 is max(0, min(PD - 1, N)),
        O is -round(N1 * (CD - PD) / (PD - 1))
    ;   O = 0
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
