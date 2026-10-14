:- module(tui_terminal,
          [
            ansi_bell/0,
            ansi_csi/1,
            ansi_reset/0,
            ansi_hide_cursor/0,
            ansi_show_cursor/0,
            ansi_save_cursor/0,
            ansi_restore_cursor/0,
            ansi_set_cursor/2,
            ansi_run/1,
            tty_request_size/0,
            wait_for_input/0,
            get_single_input/1
          ]).

/** <module> ANSI terminal I/O

Escape sequence output and keyboard input decoding for ANSI terminals.
*/

:- use_module(library(dcg/basics)).
:- use_module(library(ansi_term)).


'#output'.

% ANSI escape helpers — thin wrappers over CSI sequences.

ansi_bell :-
    format('\007').

ansi_csi(Escaped) :-
    format("~s~s", [[27, 91], Escaped]).

ansi_reset :-
    format("\ec").

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

% Ask the terminal for its size. The reply arrives as input, decoded by
% get_single_input/1 as terminal_size(Cols, Rows).
tty_request_size :-
    flush_output,
    ansi_save_cursor,
    ansi_set_cursor(1000, 1000),
    ansi_csi("6n"),
    ansi_restore_cursor,
    flush_output.


'#input'.

%!  wait_for_input is det.
%
%  Block until a single input event is available, then discard it.
wait_for_input :-
    get_single_input(_).

%!  get_single_input(-Event) is semidet.
%
%  Read one input event from the terminal. Handles escape sequences
%  (arrow keys, function keys, etc.) and control characters. Event
%  is an atom like up, down, return, tab, or a single character atom
%  for printable keys. Blocks until input is available.
get_single_input(I) :-
    get_single_char(H),
    (  H = -1
    -> fail

    ;  H \= 27
    -> code_value(H, I)
    ;  (  \+ wait_for_input([user_input], [user_input], -1)
       -> code_value(27, I)

       ;  peek_code(27)
       -> get_code(_),
          code_value(27, I)

       ;  read_escseq([ 27  |T ]-T, I)
       -> true
    )
    ), !.

read_escseq(L-T, Code) :-
    get_code(C),
    ( T = [C], codes_value(L, Code)
    -> true
    ;  wait_for_input([user_input], [user_input], -1)
    -> T = [C | T2],
       read_escseq(L-T2, Code)
    ;  T = [],
       Code = escseq(L)
    ).

% Escape sequence decoding tables.

codes_value(I, V) :-
    escape_codes_value(I, V).

escape_codes_value([27, 91  | Codes], terminal_size(X,Y)) :-
   phrase((integer(Y), [59], integer(X), [82]), Codes, []), !.
escape_codes_value([27, 91  |Codes], V) :-
    atom_codes(Atom, Codes),
    once(escaped_atom_value(Atom, V)).

escaped_atom_value('1~', home).
escaped_atom_value('2~', insert).
escaped_atom_value('3~', delete).
escaped_atom_value('4~', end).
escaped_atom_value('5~', page_up).
escaped_atom_value('6~', page_down).
escaped_atom_value('A', up).
escaped_atom_value('B', down).
escaped_atom_value('C', right).
escaped_atom_value('D', left).
escaped_atom_value('F', end).
escaped_atom_value('H', home).
escaped_atom_value('11~', f1).
escaped_atom_value('12~', f2).
escaped_atom_value('13~', f3).
escaped_atom_value('14~', f4).
escaped_atom_value('15~', f5).
escaped_atom_value('17~', f6).
escaped_atom_value('18~', f7).
escaped_atom_value('19~', f8).
escaped_atom_value('20~', f9).
escaped_atom_value('21~', f10).
escaped_atom_value('23~', f11).
escaped_atom_value('24~', f12).
escaped_atom_value('25~', f13).
escaped_atom_value('26~', f14).
escaped_atom_value('28~', f15).
escaped_atom_value('29~', f16).

% Control character code table.

code_cntrl(1, start_of_heading).
code_cntrl(2, start_of_text).
code_cntrl(3, interrupt).
code_cntrl(4, eof).
code_cntrl(5, enquiry).
code_cntrl(6, acknowledge).
code_cntrl(7, bell).
code_cntrl(8, backspace).
code_cntrl(9, tab).
code_cntrl(10, linefeed).
code_cntrl(11, vertical_tab).
code_cntrl(12, formfeed).
code_cntrl(13, return).
code_cntrl(24, cancel).
code_cntrl(14, shift_out).
code_cntrl(15, shift_in).
code_cntrl(19, device_control_3).
code_cntrl(20, device_control_4).
code_cntrl(27, escape).
code_cntrl(127, delete).

code_value(C, V) :- code_cntrl(C, V).
code_value(C, V) :-
    \+ code_type(C, cntrl),
    char_code(V, C).
