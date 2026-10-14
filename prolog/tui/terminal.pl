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
            ansi_kitty_keyboard_query/0,
            ansi_kitty_keyboard_push/1,
            ansi_kitty_keyboard_pop/0
          ]).

/** <module> ANSI terminal output

Escape sequences for ANSI terminals. Replies to queries arrive as input;
see tui/input.pl for decoding.
*/

:- use_module(library(ansi_term)).


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

% Write Chars at X-Y in Style (a list of ansi_format/3 attributes).
ansi_run((X-Y)-(Style-Chars)) :-
    ansi_set_cursor(X, Y),
    ansi_format(Style, '~s', [Chars]).


'#queries'.

% Every terminal replies, as device_attributes(Params). Sent after
% another query, its reply marks that the other reply is not coming.
ansi_primary_device_attributes :-
    ansi_csi("c").


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
