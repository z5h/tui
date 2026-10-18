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
            ansi_primary_device_attributes/0,
            ansi_bracketed_paste_on/0,
            ansi_bracketed_paste_off/0,
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

:- use_module(library(ansi_term)).
:- use_module(library(base64)).


'#output'.

% ANSI escape helpers — thin wrappers over CSI sequences.

ansi_bell :-
    format('\007').

ansi_csi(Escaped) :-
    format("~s~s", [[27, 91], Escaped]).

% Full reset (RIS): also resets modes, such as Kitty keyboard enhancements.
ansi_reset :-
    format("\ec").

% Erase the display, leaving modes as they are.
ansi_clear :-
    ansi_csi("2J").

ansi_hide_cursor :-
    ansi_csi("?25l").

ansi_show_cursor :-
    ansi_csi("?25h").

ansi_save_cursor :-
    ansi_csi("s").

ansi_restore_cursor :-
    ansi_csi("u").

ansi_set_cursor(X, Y) :-
    format('\e[~w;~wH', [Y, X]).

% Write Chars at X-Y in Style (a list of ansi_format/3 attributes). A
% char is one cell, but may be several codepoints (an image placeholder).
ansi_run((X-Y)-(Style-Chars)) :-
    ansi_set_cursor(X, Y),
    atomic_list_concat(Chars, Text),
    ansi_format(Style, '~a', [Text]).


'#queries'.

% Every terminal replies, as device_attributes(Params). Sent after
% another query, its reply marks that the other reply is not coming.
ansi_primary_device_attributes :-
    ansi_csi("c").


'#bracketed_paste'.

% While on, pasted text arrives between ESC [200~ and ESC [201~.
ansi_bracketed_paste_on :-
    ansi_csi("?2004h").

ansi_bracketed_paste_off :-
    ansi_csi("?2004l").


'#kitty_keyboard'.

% Kitty keyboard protocol:
% https://sw.kovidgoyal.net/kitty/keyboard-protocol/

% A supporting terminal replies kitty_keyboard(Flags).
ansi_kitty_keyboard_query :-
    ansi_csi("?u").

% Enable the enhancements in Flags (1 disambiguates escape codes),
% saving the current ones.
ansi_kitty_keyboard_push(Flags) :-
    format('\e[>~wu', [Flags]).

% Restore the enhancements saved by the last push.
ansi_kitty_keyboard_pop :-
    ansi_csi("<u").


'#kitty_graphics'.

% Kitty graphics protocol:
% https://sw.kovidgoyal.net/kitty/graphics-protocol/
%
% Commands are APC sequences, ESC _ G keys ; payload ESC \. With q=2 the
% terminal sends no reply; only the query is answered.

% A supporting terminal replies kitty_graphics(Reply), Reply ending in
% ";OK". Uses image id 31, which is not kept.
ansi_kitty_graphics_query :-
    ansi_kitty_graphics("i=31,s=1,v=1,a=q,t=d,f=24", "AAAA").

% Upload Source (see tui/image.pl) as image Id. The base64 payload goes in
% chunks of at most 4096 bytes, each but the last marked m=1.
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

% The virtual placement of image Id in W×H cells, shown wherever its
% placeholders are drawn. Placement id 1 is always used, so a new
% placement replaces the previous one.
ansi_kitty_image_place(Id, W-H) :-
    format(string(Keys), "a=p,U=1,i=~w,p=1,c=~w,r=~w,q=2", [Id, W, H]),
    ansi_kitty_graphics(Keys, "").

ansi_kitty_graphics(Keys, "") :- !,
    format("\e_G~w\e\\", [Keys]).
ansi_kitty_graphics(Keys, Payload) :-
    format("\e_G~w;~w\e\\", [Keys, Payload]).
