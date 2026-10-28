:- module(tui_components, []).

/** <module> Ready-made TUI components

Ready-made, styled components: `check_box(Title, Bool)`,
`button(Label)`, `input(Width, Placeholder, Value)`, `rule(Width)`,
`frame(Size, Contents)` (and `frame/3`), `titled_frame(Size, Title,
Contents)` (and `titled_frame/4`) and `scroll(Size, Offset, Content)`.
Load library(tui/components) to use them.

They are aliases, not predicates: draw them as terms in a view. Each is
documented under tui:alias_drawable/2, in the section for this library.

They are defined through the hooks tui:alias_drawable/2 and
tui:at_event_is/3, from the core drawables of library(tui).
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
A check box, shown as ``[x] Title``, ``[ ] Title`` or ``[-] Title`` for
Bool `true`, `false` or `partial`, highlighted when focused. A unit (see
`unit(Drawable)`).

  - `' '`, `return` or `mouse(press, left)` become `check_box-NewBool`:
    `true` becomes `false`, the others `true`
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
A button, shown as ``┃Label┃``, highlighted when focused. A unit (see
`unit(Drawable)`).

  - `' '`, `return` or `mouse(press, left)` become `button-pressed`
*/
tui:alias_drawable(button(Label), unit(hover([negative], Content, G))) :-
    % Focused, the caps swap to half blocks: in negative, a pill with
    % half-cell padding.
    Content = hover([char('▌')], '┃', G) .> Label .> hover([char('▐')], '┃', G).

tui:at_event_is(button(_), _-' ', button-pressed).
tui:at_event_is(button(_), _-return, button-pressed).
tui:at_event_is(button(_), _-mouse(press, left), button-pressed).

/*<tui> input(Width, Placeholder, Value)
A one-line text field Width wide, shown as ``> `` and an underlined
field holding Value, or ``<Placeholder>`` while Value is unbound (nothing
if Placeholder is `''`). Highlighted when focused, with the cursor shown
in it; the cursor stays within the text.

  - a printable character (a one-character atom) is inserted at the
    cursor
  - `backspace` deletes before the cursor, `delete` at it
  - `paste(Text)` inserts Text, its line breaks as spaces

Each edit becomes `input-NewValue`, NewValue a string.
*/
tui:alias_drawable(input(W, PlaceholderA, ValueA), hover([negative], D, G)) :-
    % Focused, prompt and field are negative, and the field loses its
    % underline (in negative it would show as a slice cut from the bar)
    % and the placeholder.
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

% The cursor is kept where text can be edited (trailing spaces are text,
% the padding to Width is not). Arriving (arrived(Dir), a left press)
% past the end of the text, or on the prompt, it moves to the nearest
% such cell; after an edit, cursor_by keeps it after the edit. An edit
% that changes nothing (backspace at the start, delete at the end) is
% noop, so that it does not bubble on.
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
A horizontal rule Width cells long, a hairline along the baseline.
*/
tui:alias_drawable(rule(W), style([underline], Spaces)) :-
    repeat_char_string(W, ' ', Spaces).

/*<tui> frame(Size, Contents)
A W×H frame (Size being W-H): rules above and below, no side walls, and
Contents clipped to the (W-2)×(H-2) inside, from 1-1. It covers what is
under it.
*/
tui:alias_drawable(frame(W-H, Contents), frame(W-H, Contents, _)).

/*<tui> frame(Size, Contents, Extent)
As `frame(Size, Contents)`, with Extent unified with the furthest cell
Contents draws, MaxX-MaxY.
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
A frame (see `frame(Size, Contents)`) with Title, any drawable, at the
start of its top rule.
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
Content in a frame (see `frame(Size, Contents)`), scrolled by Offset,
X-Y (each 0 or negative), with a scrollbar on each axis where it does
not fit. A scrollbar is highlighted when focused, and is a unit (see
`unit(Drawable)`).

  - `shift+up`, `shift+down`, `shift+left` and `shift+right` drag what
    is under the cursor: the content a row or column, or on a scrollbar
    its thumb
  - `page_up` and `page_down` scroll a page
  - `mouse(scroll, Dir)` scrolls a row or column

Each becomes `scroll-NewOffset`; at the limits, nothing.
*/
tui:alias_drawable(scroll(W-H, X-Y, Content), scroll_view(X-Y, MaxH-MaxV, PH, [FramePart | Bars])) :-
    HM1 is H - 1,
    WM1 is W - 1,

    drawable_raw_extent(frame(W-H, X-Y-Content, EX-EY), FramePart, _),

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
Part of `scroll(Size, Offset, Content)`; not meant to be drawn directly.
*/
tui:alias_drawable(scroll_view(_, _, _, D), D).

/*<tui> vscroll(Drawable, Step)
Part of `scroll(Size, Offset, Content)`; not meant to be drawn directly.
*/
tui:alias_drawable(vscroll(D, _), unit(D)).

/*<tui> hscroll(Drawable, Step)
Part of `scroll(Size, Offset, Content)`; not meant to be drawn directly.
*/
tui:alias_drawable(hscroll(D, _), unit(D)).

% These are aliases, not helpers, because events find components only on
% the alias stack. scroll_view/4 is drawn around the frame and the bars,
% carrying what the scroll's events need: the offset, Limits MaxH-MaxV
% (how far the content can scroll on each axis, 0 or positive), and the
% viewport's height. vscroll/2 and hscroll/2 are the bars, each a unit;
% on one, Shift+arrows along its axis become thumb_dragged(Dir, Step),
% which scroll_view/4 turns into scrolling the content Step rows or
% columns the other way.

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
