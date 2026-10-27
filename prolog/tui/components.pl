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

/*<tui> check_box(Title, Bool)
A toggleable checkbox: ``[x]``, ``[ ]`` or ``[-]`` (Bool true, false or
partial), then Title. With the cursor on it, box and title are
negative together. It is a unit (`unit(Drawable)`): the cursor is
hidden on it, and an arrow moves it out in one keypress.

Events produced:

  - `check_box-NewBool` on `' '` (space), `return` or
    `mouse(press, left)`: true becomes false, false and partial become
    true
*/
tui:alias_drawable(check_box(Title, Bool), unit(hover([negative], Box .> ' ' .> Title))) :-
    bool_box(Bool, Box).

bool_box(true, '[x]').
bool_box(false, '[ ]').
bool_box(partial, '[-]').

bool_toggled(true, false).
bool_toggled(false, true).
bool_toggled(partial, true).

tui:at_event_is(check_box(_Title, Bool), _-' ', check_box-T) :- bool_toggled(Bool, T).
tui:at_event_is(check_box(_Title, Bool), _-return, check_box-T) :- bool_toggled(Bool, T).
tui:at_event_is(check_box(_Title, Bool), _-mouse(press, left), check_box-T) :- bool_toggled(Bool, T).

/*<tui> button(Label)
A button, shown as ``┃Label┃``. With the cursor on it, it is negative
and its caps become ``▌`` and ``▐``, a pill with half-cell padding. It
is a unit (`unit(Drawable)`): the cursor is hidden on it, and an arrow
moves it out in one keypress.

Events produced:

  - `button-pressed` on `' '` (space), `return` or `mouse(press, left)`
*/
tui:alias_drawable(button(Label), unit(hover([negative], Content, G))) :-
    Content = hover([char('▌')], '┃', G) .> Label .> hover([char('▐')], '┃', G).

tui:at_event_is(button(_), _-' ', button-pressed).
tui:at_event_is(button(_), _-return, button-pressed).
tui:at_event_is(button(_), _-mouse(press, left), button-pressed).

/*<tui> input(Width, Placeholder, Value)
A one-line text field Width wide, underlined, after a bold ``> ``.
Shows Value, or while Value is unbound, the Placeholder in angle
brackets, italic (none if Placeholder is empty). Text beyond Width is
not shown. With the cursor on it, prompt and field are negative and the
field loses its underline (a negative underline would show as a slice
cut from the bar); the cursor is shown in it, and the placeholder is
not.

The cursor stays where text can be edited: on `arrived(Dir)` or
`mouse(press, left)` past the end of the text (trailing spaces are
text; the padding to Width is not), or on the ``> ``, it moves to the
nearest such cell.

With the cursor in the field:

  - a one-character atom (code 32 or above, but not 127) is inserted
    at the cursor (at the end of the text, if the cursor is past it),
    and the cursor advances
  - `backspace` deletes before the cursor, `delete` at it
  - `paste(Text)` inserts Text, its line breaks as spaces

Events produced:

  - `input-NewValue`, NewValue a string, followed by `cursor_by(DX-0)`
    if the cursor must move to stay after the edit
  - `cursor_by(DX-0)` alone, moving an arriving cursor to where text can
    be edited
  - `noop` for an edit that changes nothing (`backspace` at the start,
    `delete` at the end), so that it does not bubble on
*/
tui:alias_drawable(input(W, PlaceholderA, ValueA), hover([negative], D, G)) :-
    atomics_to_string([PlaceholderA], Placeholder),
    (  var(ValueA)
    -> (   Placeholder == ""
       ->  Shown = ""
       ;   atomics_to_string(["<", Placeholder, ">"], Shown)
       ),
       string_length_adjusted(Shown, W, Displayed),
       Field = unhovered([underline], hover([char(' ')], style([italic], Displayed), G), G)
    ;  atomics_to_string([ValueA], Value),
       string_length_adjusted(Value, W, Displayed),
       Field = unhovered([underline], Displayed, G)
    ),
    D = [style([bold], '> '),
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

/*<tui> rule(Width)
A horizontal rule Width cells long: spaces drawn underlined, a
hairline along the baseline.
*/
tui:alias_drawable(rule(W), style([underline], Spaces)) :-
    repeat_char_string(W, ' ', Spaces).

/*<tui> frame(Size, Contents)
A frame W×H, Size being W-H, containing Contents in a viewport. Its
top and bottom rows are rules across the full width; it has no side
walls. The viewport is (W-2)×(H-2), from 1-1, leaving a blank column
either side (the right one takes a vertical scrollbar, see
`scroll(Size, Offset, Content)`). The whole frame is cleared before
rendering.
*/
tui:alias_drawable(frame(W-H, Contents), frame(W-H, Contents, _)).

/*<tui> frame(Size, Contents, Extent)
As `frame(Size, Contents)`; Extent is unified with the MaxX-MaxY of the
content (useful for scrolling).
*/
tui:alias_drawable(frame(W-H, Contents, Extent), [clear(W-H), Top, Bottom, Port]) :-
    (  W > 1, H > 1
    -> true
    ;  domain_error(valid_window_size, W-H)
    ),
    HM1 is H - 1,
    Top = rule(W),
    Bottom = 0-HM1-rule(W),
    PW is W - 2,
    PH is H - 2,
    Port = 1-1-port(PW-PH, Contents, Extent).

/*<tui> titled_frame(Size, Title, Contents)
A frame (see `frame(Size, Contents)`) with Title in its top rule, from
its first column, underlined and cut off at the frame's edge. Title is
any drawable.
*/
tui:alias_drawable(titled_frame(W-H, Title, Contents), titled_frame(W-H, Title, Contents, _)).

/*<tui> titled_frame(Size, Title, Contents, Extent)
As `titled_frame(Size, Title, Contents)`, with Extent as in
`frame(Size, Contents, Extent)`.
*/
tui:alias_drawable(titled_frame(W-H, Title, Contents, Extent), [FramePart, TitlePart]) :-
    FramePart = frame(W-H, Contents, Extent),
    TitlePart = style([underline], port(W-1, Title)).


'#scrolling'.

/*<tui> scroll(Size, Offset, Content)
A scrollable frame (see `frame(Size, Contents)`). Content is rendered
in a W×H frame's viewport (Size being W-H), offset by Offset,
ScrollX-ScrollY (each 0 or negative). On each axis where the content
does not fit, a scrollbar shows its thumb, with half-cell resolution
and no track: vertical in the frame's right column, horizontal in its
bottom rule. With the cursor on a scrollbar, its thumb is solid: the
half blocks fill the whole width of the column, or the whole height of
the row. A scrollbar is a unit (`unit(Drawable)`): the cursor is hidden
on it, and an arrow moves it out in one keypress.

`shift+up`, `shift+down`, `shift+left` and `shift+right` drag what is
under the cursor, as with a mouse:

  - anywhere in the frame, the content, one row or column per press
  - on a scrollbar, along its axis, the thumb, one half-cell per press

`page_up` and `page_down` move by a page (the viewport's height less
one row, at least one), anywhere in the frame. With the mouse (see
app/5), `mouse(scroll, Dir)` scrolls the content a row or column at a
time.

Events produced:

  - `scroll-(NewX-NewY)`, the new offset
  - `noop` for an event that would move past the limits, so that it
    does not bubble on
*/
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
        HBars = [1-HM1-hscroll(style([underline], HScroll), StepH)]
    ;   HBars = []
    ),
    (   CH > PH
    ->  port_content_offset_axis_scrollbar(PH, CH, Y, v, VScroll),
        port_content_step(PH, CH, StepV),
        VBars = [WM1-1-vscroll(VScroll, StepV)]
    ;   VBars = []
    ),
    append(HBars, VBars, Bars).

/*<tui> scroll_view(Offset, Limits, PageHeight, Drawable)
Draws Drawable. Meant for `scroll(Size, Offset, Content)`, which draws
its frame and scrollbars with it, so that its events find, on the alias
stack, what they need: Offset, the content's offset; Limits, MaxH-MaxV,
how far the content can scroll on each axis (0 or positive); and
PageHeight, the viewport's height. The events it takes are those of
`scroll(Size, Offset, Content)`.
*/
tui:alias_drawable(scroll_view(_, _, _, D), D).

/*<tui> vscroll(Drawable, Step)
Draws Drawable, a vertical scrollbar. Meant for
`scroll(Size, Offset, Content)`: on it, `shift+up` and `shift+down`
become `thumb_dragged(Dir, Step)`, which the enclosing
`scroll_view(Offset, Limits, PageHeight, Drawable)` turns into
scrolling the content Step rows the other way. It is a unit
(`unit(Drawable)`): the cursor is hidden on it, and an arrow moves it
out in one keypress.
*/
tui:alias_drawable(vscroll(D, _), unit(D)).

/*<tui> hscroll(Drawable, Step)
Draws Drawable, a horizontal scrollbar. Meant for
`scroll(Size, Offset, Content)`: on it, `shift+left` and `shift+right`
become `thumb_dragged(Dir, Step)`, which the enclosing
`scroll_view(Offset, Limits, PageHeight, Drawable)` turns into
scrolling the content Step columns the other way. It is a unit
(`unit(Drawable)`): the cursor is hidden on it, and an arrow moves it
out in one keypress.
*/
tui:alias_drawable(hscroll(D, _), unit(D)).

% On a scrollbar, Shift+arrows along its axis drag the thumb by Step.
tui:at_event_is(vscroll(_, Step), _-(shift+D), thumb_dragged(D, Step)) :-
    memberchk(D, [up, down]).
tui:at_event_is(hscroll(_, Step), _-(shift+D), thumb_dragged(D, Step)) :-
    memberchk(D, [left, right]).

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

% Scroll thumb characters: each cell shows two halves, the thumb (f) or
% nothing (s), so the thumb has half-cell resolution. There is no track.
% The vertical thumb takes the right half of its column, a half-cell gap
% from the content; the horizontal one the lower half of its row, on the
% rule.

% Focused, the thumb is solid: each glyph swaps to the one filling its
% halves across the whole cell.

scroll_char(h, s, s, ' ', ' ').
scroll_char(h, f, f, '▄', '█').
scroll_char(h, s, f, '▗', '▐').
scroll_char(h, f, s, '▖', '▌').

scroll_char(v, s, s, ' ', ' ').
scroll_char(v, f, f, '▐', '█').
scroll_char(v, s, f, '▗', '▄').
scroll_char(v, f, s, '▝', '▀').

% The scrollbar along axis S (h or v) for a port PD cells long, showing
% content CD long (CD > PD) scrolled to offset CO (0 or negative). Its
% thumb starts at the first half at offset 0, and at the last half the
% thumb can reach at the largest offset. Its cells are one hover group,
% so that the thumb is solid while the cursor is anywhere on it.
port_content_offset_axis_scrollbar(PD, CD, CO, S, hover([], Cells, G)) :-
    port_content_thumb(PD, CD, Len, Travel),
    Start is max(0, min(Travel, round(Travel * -CO / (CD - PD)))),
    End is Start + Len,
    axis_thumb_cells_scrollbar(S, Start-End, G, 0, PD, Cells).

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
% to (not including) End, its glyphs swapped in hover group G.
axis_thumb_cells_scrollbar(_, _, _, M, M, []) :- !.
axis_thumb_cells_scrollbar(S, Thumb, G, N, M, [X-Y-hover([char(Solid)], Char, G) | Cells]) :-
    I is 2 * N,
    J is I + 1,
    thumb_half_weight(Thumb, I, A),
    thumb_half_weight(Thumb, J, B),
    scroll_char(S, A, B, Char, Solid),
    (   S = h
    ->  X = N, Y = 0
    ;   X = 0, Y = N
    ),
    N1 is N + 1,
    axis_thumb_cells_scrollbar(S, Thumb, G, N1, M, Cells).

% Half I is thick (f) inside the thumb, thin (s) outside it.
thumb_half_weight(Start-End, I, W) :-
    (   I >= Start,
        I < End
    ->  W = f
    ;   W = s
    ).
