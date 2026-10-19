:- module(tui_terminal,
          [
            ansi_bell/0,
            ansi_csi/1,
            ansi_reset/0,
            ansi_clear/0,
            ansi_hide_cursor/0,
            ansi_show_cursor/0,
            ansi_save_cursor/0,
            ansi_restore_cursor/0,
            ansi_set_cursor/2,
            ansi_run/1,
            attributes_sgr/2,
            ansi_primary_device_attributes/0,
            ansi_bracketed_paste_on/0,
            ansi_bracketed_paste_off/0,
            ansi_mouse_on/0,
            ansi_mouse_off/0,
            ansi_kitty_keyboard_query/0,
            ansi_kitty_keyboard_push/1,
            ansi_kitty_keyboard_pop/0,
            ansi_kitty_graphics_query/0,
            ansi_kitty_image_transmit/2,
            ansi_kitty_image_place/2
          ]).

/** <module> ANSI terminal output

Escape sequences for ANSI terminals. Replies to queries arrive as input;
see tui/input.pl for decoding.
*/

:- use_module(library(apply)).
:- use_module(library(base64)).
:- use_module(library(error)).


'#output'.

% The predicates of this module write to current_output and do not
% flush; the caller flushes.

%!  ansi_bell is det.
%
%  Write the bell character.
ansi_bell :-
    format('\007').

%!  ansi_csi(+Escaped) is det.
%
%  Write a Control Sequence Introducer (ESC [) followed by Escaped, a
%  string or code list.
ansi_csi(Escaped) :-
    format("~s~s", [[27, 91], Escaped]).

%!  ansi_reset is det.
%
%  Full reset (RIS): also resets modes, such as Kitty keyboard
%  enhancements.
ansi_reset :-
    format("\ec").

%!  ansi_clear is det.
%
%  Erase the display, leaving modes as they are.
ansi_clear :-
    ansi_csi("2J").

%!  ansi_hide_cursor is det.
%!  ansi_show_cursor is det.
%
%  Hide or show the terminal's cursor.
ansi_hide_cursor :-
    ansi_csi("?25l").

ansi_show_cursor :-
    ansi_csi("?25h").

%!  ansi_save_cursor is det.
%!  ansi_restore_cursor is det.
%
%  Save the cursor's position, and restore the saved one.
ansi_save_cursor :-
    ansi_csi("s").

ansi_restore_cursor :-
    ansi_csi("u").

%!  ansi_set_cursor(+X, +Y) is det.
%
%  Move the cursor to column X, row Y, both counted from 1.
ansi_set_cursor(X, Y) :-
    format('\e[~w;~wH', [Y, X]).

%!  ansi_run(+Run) is det.
%
%  Write Run, (X-Y)-(Style-Chars): Chars at X-Y in Style (see
%  attributes_sgr/2), then reset the style. A char is one cell, but may
%  be several codepoints (an image placeholder).
ansi_run((X-Y)-([]-Chars)) :- !,
    ansi_set_cursor(X, Y),
    atomic_list_concat(Chars, Text),
    format("~a", [Text]).
ansi_run((X-Y)-(Style-Chars)) :-
    ansi_set_cursor(X, Y),
    attributes_sgr(Style, SGR),
    atomic_list_concat(Chars, Text),
    format("\e[~am~a\e[0m", [SGR, Text]).


'#styles'.

%!  attributes_sgr(+Attrs, -SGR) is det.
%
%  SGR is the parameters of the Select Graphic Rendition sequence that
%  sets Attrs, e.g. '1;31' for [bold, fg(red)]. Attributes are reset,
%  bold, faint, italic, underline, negative and crossed_out; colours are
%  fg(C), bg(C), and the bright hfg(C) and hbg(C), C being black, red,
%  green, yellow, blue, magenta, cyan, white or default (fg and bg only),
%  or an index 0..255; and fg(R, G, B) and bg(R, G, B), each 0..255.
%
%  @error domain_error(sgr_attribute, A) for any other attribute A.
attributes_sgr(Attrs, SGR) :-
    foldl(attribute_parameters, Attrs, Ps, []),
    atomic_list_concat(Ps, ';', SGR).

attribute_parameters(A, Ps0, Ps) :-
    (   attribute_parameters_(A, Ps0, Ps)
    ->  true
    ;   domain_error(sgr_attribute, A)
    ).

attribute_parameters_(reset)          --> [0].
attribute_parameters_(bold)           --> [1].
attribute_parameters_(faint)          --> [2].
attribute_parameters_(italic)         --> [3].
attribute_parameters_(underline)      --> [4].
attribute_parameters_(negative)       --> [7].
attribute_parameters_(crossed_out)    --> [9].
attribute_parameters_(fg(C))          --> color_parameters(C, 30, 38).
attribute_parameters_(bg(C))          --> color_parameters(C, 40, 48).
attribute_parameters_(hfg(C))         --> { C \== default }, color_parameters(C, 90, 38).
attribute_parameters_(hbg(C))         --> { C \== default }, color_parameters(C, 100, 48).
attribute_parameters_(fg(R, G, B))    --> rgb_parameters(38, R, G, B).
attribute_parameters_(bg(R, G, B))    --> rgb_parameters(48, R, G, B).

% A named colour is Base plus its number; an index is Extended;5;N.
color_parameters(C, Base, _) -->
    { atom(C),
      color_number(C, N),
      P is Base + N },
    [P].
color_parameters(C, _, Extended) -->
    { integer(C),
      between(0, 255, C) },
    [Extended, 5, C].

rgb_parameters(Extended, R, G, B) -->
    { maplist(integer, [R, G, B]),
      maplist(between(0, 255), [R, G, B]) },
    [Extended, 2, R, G, B].

color_number(black,   0).
color_number(red,     1).
color_number(green,   2).
color_number(yellow,  3).
color_number(blue,    4).
color_number(magenta, 5).
color_number(cyan,    6).
color_number(white,   7).
color_number(default, 9).


'#queries'.

%!  ansi_primary_device_attributes is det.
%
%  Request the primary device attributes. Every terminal replies, as
%  device_attributes(Params). Sent after another query, its reply marks
%  that the other reply is not coming.
ansi_primary_device_attributes :-
    ansi_csi("c").


'#bracketed_paste'.

%!  ansi_bracketed_paste_on is det.
%!  ansi_bracketed_paste_off is det.
%
%  Turn bracketed paste on or off. While on, pasted text arrives between
%  ESC [200~ and ESC [201~.
ansi_bracketed_paste_on :-
    ansi_csi("?2004h").

ansi_bracketed_paste_off :-
    ansi_csi("?2004l").


'#mouse'.

%!  ansi_mouse_on is det.
%!  ansi_mouse_off is det.
%
%  Turn mouse reporting on or off. While on, the terminal reports
%  presses and releases (mode 1000), motion with a button held (1002),
%  as SGR reports (1006): see tui/input.pl. The terminal's own text
%  selection then needs a modifier (usually shift).
ansi_mouse_on :-
    ansi_csi("?1000h"),
    ansi_csi("?1002h"),
    ansi_csi("?1006h").

ansi_mouse_off :-
    ansi_csi("?1006l"),
    ansi_csi("?1002l"),
    ansi_csi("?1000l").


'#kitty_keyboard'.

% Kitty keyboard protocol:
% https://sw.kovidgoyal.net/kitty/keyboard-protocol/

%!  ansi_kitty_keyboard_query is det.
%
%  Ask for the Kitty keyboard protocol's flags. A supporting terminal
%  replies kitty_keyboard(Flags).
ansi_kitty_keyboard_query :-
    ansi_csi("?u").

%!  ansi_kitty_keyboard_push(+Flags) is det.
%
%  Enable the enhancements in Flags (1 disambiguates escape codes),
%  saving the current ones.
ansi_kitty_keyboard_push(Flags) :-
    format('\e[>~wu', [Flags]).

%!  ansi_kitty_keyboard_pop is det.
%
%  Restore the enhancements saved by the last push.
ansi_kitty_keyboard_pop :-
    ansi_csi("<u").


'#kitty_graphics'.

% Kitty graphics protocol:
% https://sw.kovidgoyal.net/kitty/graphics-protocol/
%
% Commands are APC sequences, ESC _ G keys ; payload ESC \. With q=2 the
% terminal sends no reply; only the query is answered.

%!  ansi_kitty_graphics_query is det.
%
%  Ask whether the Kitty graphics protocol is supported. A supporting
%  terminal replies kitty_graphics(Reply), Reply ending in ";OK". Uses
%  image id 31, which is not kept.
ansi_kitty_graphics_query :-
    ansi_kitty_graphics("i=31,s=1,v=1,a=q,t=d,f=24", "AAAA").

%!  ansi_kitty_image_transmit(+Id, +Source) is det.
%
%  Upload Source (see image/3 in tui/image.pl) as image Id. The base64
%  payload goes in chunks of at most 4096 bytes, each but the last
%  marked m=1.
ansi_kitty_image_transmit(Id, file(Path)) :- !,
    base64_encoded(Path, Payload, [encoding(utf8)]),
    format(string(Keys), "a=t,t=f,f=100,i=~w,q=2", [Id]),
    ansi_kitty_graphics(Keys, Payload).
ansi_kitty_image_transmit(Id, Source) :-
    source_keys_bytes(Source, Keys0, Bytes),
    text_to_string(Bytes, Plain),
    base64(Plain, Payload),
    format(string(Keys), "a=t,~w,i=~w,q=2", [Keys0, Id]),
    payload_chunks(Payload, Chunks),
    keys_chunks_transmitted(Keys, Chunks).

source_keys_bytes(png(Bytes), "f=100", Bytes).
source_keys_bytes(rgba(W-H, Bytes), Keys, Bytes) :-
    format(string(Keys), "f=32,s=~w,v=~w", [W, H]).
source_keys_bytes(rgb(W-H, Bytes), Keys, Bytes) :-
    format(string(Keys), "f=24,s=~w,v=~w", [W, H]).

payload_chunks(Payload, Chunks) :-
    string_length(Payload, N),
    (   N =< 4096
    ->  Chunks = [Payload]
    ;   sub_string(Payload, 0, 4096, _, Chunk),
        sub_string(Payload, 4096, _, 0, Rest),
        Chunks = [Chunk | Chunks1],
        payload_chunks(Rest, Chunks1)
    ).

keys_chunks_transmitted(Keys, [Chunk]) :- !,
    ansi_kitty_graphics(Keys, Chunk).
keys_chunks_transmitted(Keys, [Chunk | Chunks]) :-
    string_concat(Keys, ",m=1", Keys1),
    ansi_kitty_graphics(Keys1, Chunk),
    chunks_transmitted(Chunks).

chunks_transmitted([Chunk]) :- !,
    ansi_kitty_graphics("m=0,q=2", Chunk).
chunks_transmitted([Chunk | Chunks]) :-
    ansi_kitty_graphics("m=1,q=2", Chunk),
    chunks_transmitted(Chunks).

%!  ansi_kitty_image_place(+Id, +Size) is det.
%
%  The virtual placement of image Id in W×H cells, Size being W-H, shown
%  wherever its placeholders are drawn. Placement id 1 is always used,
%  so a new placement replaces the previous one.
ansi_kitty_image_place(Id, W-H) :-
    format(string(Keys), "a=p,U=1,i=~w,p=1,c=~w,r=~w,q=2", [Id, W, H]),
    ansi_kitty_graphics(Keys, "").

ansi_kitty_graphics(Keys, "") :- !,
    format("\e_G~w\e\\", [Keys]).
ansi_kitty_graphics(Keys, Payload) :-
    format("\e_G~w;~w\e\\", [Keys, Payload]).
