:- module(tui_input,
          [
            codes_events_pending/3,
            pending_events_flushed/2,
            pending_paste_open/1
          ]).

/** <module> Terminal input decoding

Decodes the codes a terminal sends into events. Understands both the
legacy xterm encoding and the Kitty keyboard protocol, at all times.

Events:

  * A key: a single-character atom for printable keys ('a', 'A', ' '),
    or a name: up, down, left, right, home, end, begin, insert, delete,
    page_up, page_down, f1..f35, escape, return, tab, backspace, or
    key(Code) for other Kitty functional keys.
  * A modified key: Mods+Key, with modifiers in the order ctrl, alt,
    shift, super, hyper, meta, and the key last, e.g. ctrl+shift+up.
    Letters with modifiers use the lowercase letter (ctrl+a). Shift
    alone on a printable key gives the shifted character ('A').
  * paste(Text): text pasted while bracketed paste is on, as a string.
    Line breaks are normalised to "\n".
  * Terminal replies: kitty_keyboard(Flags), device_attributes(Params),
    kitty_graphics(Reply) (Reply a string, e.g. "i=31;OK").
  * unknown_input(Codes) for a well-formed sequence with no meaning here.

Without the Kitty protocol some keys are indistinguishable: tab and
ctrl+i, return and ctrl+m, escape and ctrl+[ decode as tab, return and
escape.
*/


'#decoding'.

%!  codes_events_pending(+Codes, -Events, -Pending) is det.
%
%  Events decoded from Codes. Pending is a trailing incomplete escape
%  sequence, to be completed by codes that have not arrived yet.
codes_events_pending(Codes, Events, Pending) :-
    phrase(tokens(Tokens), Codes, Pending),
    maplist(token_event, Tokens, Events).

%!  pending_events_flushed(+Pending, -Events) is det.
%
%  Events for Pending once no more codes are coming: a lone escape is
%  the escape key, and escape followed by one code is that key with alt.
pending_events_flushed([], []) :- !.
pending_events_flushed([27], [escape]) :- !.
pending_events_flushed([27, C], [E]) :- !,
    token_event(alt(C), E).
pending_events_flushed(Codes, [unknown_input(Codes)]).

%!  pending_paste_open(+Pending) is semidet.
%
%  True if Pending is a paste whose end has not arrived. A paste may span
%  many reads, so it should not be flushed early.
pending_paste_open(Pending) :-
    phrase(paste_start, Pending, _).


'#tokens'.

% Complete tokens, stopping before an incomplete escape sequence.
tokens([T | Ts]) --> token(T), !, tokens(Ts).
tokens([]) --> [].

% Bracketed paste: everything up to the end marker, taken literally.
% Without the end marker the paste is incomplete.
token(paste(Codes)) --> paste_start, !, paste_codes(Codes).
% CSI: ESC [ parameter-bytes intermediate-bytes final-byte (ECMA-48).
token(T) --> [27, 0'[], !,
    csi_bytes(0x30, 0x3F, Ps),
    csi_bytes(0x20, 0x2F, Is),
    csi_end(Ps, Is, T).
% SS3: ESC O code.
token(ss3(C)) --> [27, 0'O], !, [C].
% APC: ESC _ codes ESC \ (ST). Without the ST it is incomplete; legacy
% alt+_ alone is resolved by the escape grace period.
token(apc(Codes)) --> [27, 0'_], !, apc_codes(Codes).
% Escape followed by escape: the first is the escape key.
token(char(27)) --> [27], peek(27), !.
% Escape followed by any other code: that key with alt.
token(alt(C)) --> [27, C], !.
% A lone escape is incomplete.
token(_) --> [27], !, { fail }.
token(char(C)) --> [C].

csi_bytes(Lo, Hi, [C | Cs]) --> [C], { between(Lo, Hi, C) }, !, csi_bytes(Lo, Hi, Cs).
csi_bytes(_, _, []) --> [].

% At the end of the codes the sequence is incomplete, so csi_end fails.
csi_end(Ps, Is, csi(Ps, Is, F)) --> [F], { between(0x40, 0x7E, F) }, !.
csi_end(Ps, Is, unknown(Codes)) --> peek(_), !,
    { append([27, 0'[ | Ps], Is, Codes) }.

peek(C), [C] --> [C].

paste_start --> [27, 0'[, 0'2, 0'0, 0'0, 0'~].

paste_end --> [27, 0'[, 0'2, 0'0, 0'1, 0'~].

paste_codes([]) --> paste_end, !.
paste_codes([C | Cs]) --> [C], paste_codes(Cs).

apc_codes([]) --> [27, 0'\\], !.
apc_codes([C | Cs]) --> [C], apc_codes(Cs).


'#events'.

token_event(char(C), E) :-
    code_event(C, E).
token_event(alt(C), E) :-
    code_event(C, E0),
    event_alt(E0, E).
token_event(ss3(C), E) :-
    (   letter_key(C, K)
    ->  E = K
    ;   E = unknown_input([27, 0'O, C])
    ).
token_event(csi(Ps, Is, F), E) :-
    (   csi_event(Ps, Is, F, E0)
    ->  E = E0
    ;   append([27, 0'[ | Ps], Is, Codes0),
        append(Codes0, [F], Codes),
        E = unknown_input(Codes)
    ).
token_event(unknown(Codes), unknown_input(Codes)).
token_event(apc(Codes), E) :-
    (   Codes = [0'G | Reply]
    ->  string_codes(Text, Reply),
        E = kitty_graphics(Text)
    ;   append([27, 0'_ | Codes], [27, 0'\\], All),
        E = unknown_input(All)
    ).
token_event(paste(Codes), paste(Text)) :-
    phrase(line_breaks_normalised(Normalised), Codes),
    string_codes(Text, Normalised).

% CR LF and CR become LF.
line_breaks_normalised([10 | Cs]) --> [13, 10], !, line_breaks_normalised(Cs).
line_breaks_normalised([10 | Cs]) --> [13], !, line_breaks_normalised(Cs).
line_breaks_normalised([C | Cs]) --> [C], !, line_breaks_normalised(Cs).
line_breaks_normalised([]) --> [].

code_event(0, ctrl+' ') :- !.
code_event(8, ctrl+h) :- !.
code_event(9, tab) :- !.
code_event(13, return) :- !.
code_event(27, escape) :- !.
code_event(127, backspace) :- !.
code_event(C, ctrl+K) :-
    between(1, 26, C), !,
    L is C + 0'a - 1,
    char_code(K, L).
code_event(C, ctrl+K) :-
    between(28, 31, C), !,
    L is C + 64,
    char_code(K, L).
code_event(C, K) :-
    char_code(K, C).

% Alt on a shifted letter is alt+shift on the letter.
event_alt(E0, E) :-
    event_mods_key(E0, Mods0, Key0),
    (   atom(Key0),
        atom_length(Key0, 1),
        char_type(Key0, upper(Lower))
    ->  Mods1 = [shift | Mods0],
        Key = Lower
    ;   Mods1 = Mods0,
        Key = Key0
    ),
    mods_key_event([alt | Mods1], Key, E).


'#csi'.

csi_event(Ps, [], F, E) :-
    (   Ps = [P | Rest],
        between(0x3C, 0x3F, P)
    ->  codes_params(Rest, Params),
        private_event(P, Params, F, E)
    ;   codes_params(Ps, Params),
        params_final_event(Params, F, E)
    ).

private_event(0'?, Params, 0'u, kitty_keyboard(Flags)) :-
    (   Params = [[Flags | _]]
    ->  true
    ;   Flags = 0
    ).
private_event(0'?, Params, 0'c, device_attributes(Values)) :-
    append(Params, Values).

% xterm modifyOtherKeys: CSI 27 ; mods ; code ~
params_final_event([[27], [M | _], [Code | _]], 0'~, E) :- !,
    code_key(Code, Key),
    param_mods(M, Mods),
    mods_key_event(Mods, Key, E).
params_final_event([[N | _] | More], 0'~, E) :- !,
    tilde_key(N, Key),
    params_mods(More, Mods),
    mods_key_event(Mods, Key, E).
% Kitty: CSI code ; mods u
params_final_event([[Code | _] | More], 0'u, E) :- !,
    code_key(Code, Key),
    params_mods(More, Mods),
    mods_key_event(Mods, Key, E).
params_final_event(Params, 0'Z, E) :- !,
    params_rest_mods(Params, Mods0),
    mods_key_event([shift | Mods0], tab, E).
params_final_event(Params, F, E) :-
    letter_key(F, Key),
    params_rest_mods(Params, Mods),
    mods_key_event(Mods, Key, E).

% Modifiers in the parameter after the first, if any.
params_rest_mods([_ | More], Mods) :- !,
    params_mods(More, Mods).
params_rest_mods([], []).

params_mods([[M | _] | _], Mods) :- !,
    param_mods(M, Mods).
params_mods(_, []).

% Parameters separated by ';', each a list of ':'-separated integers.
codes_params([], []) :- !.
codes_params(Codes, Params) :-
    string_codes(S, Codes),
    split_string(S, ";", "", Fields),
    maplist(field_values, Fields, Params).

field_values(Field, Values) :-
    split_string(Field, ":", "", Subs),
    convlist(sub_value, Subs, Values).

% Empty sub-parameters (defaults) are dropped.
sub_value(Sub, V) :-
    number_string(V, Sub).


'#modifiers'.

% Encoded as 1 + the sum of the bits. Lock states (64, 128) are dropped.
param_mods(M, Mods) :-
    Bits is M - 1,
    findall(Mod, ( modifier_bit(Mod, B), Bits /\ B =\= 0 ), Mods).

% In canonical order.
modifier_bit(ctrl, 4).
modifier_bit(alt, 2).
modifier_bit(shift, 1).
modifier_bit(super, 8).
modifier_bit(hyper, 16).
modifier_bit(meta, 32).

mods_key_event(Mods0, Key, E) :-
    findall(M, ( modifier_bit(M, _), memberchk(M, Mods0) ), Mods),
    (   Mods = []
    ->  E = Key
    ;   Mods = [M | Ms],
        foldl(chain_mod, Ms, M, Chain),
        E = Chain+Key
    ).

chain_mod(M, Chain0, Chain0+M).

event_mods_key(Chain+Key, Mods, Key) :- !,
    chain_mods(Chain, Mods).
event_mods_key(Key, [], Key).

chain_mods(Chain+M, Mods) :- !,
    chain_mods(Chain, Mods0),
    append(Mods0, [M], Mods).
chain_mods(M, [M]).


'#keys'.

letter_key(0'A, up).
letter_key(0'B, down).
letter_key(0'C, right).
letter_key(0'D, left).
letter_key(0'E, begin).
letter_key(0'F, end).
letter_key(0'H, home).
letter_key(0'P, f1).
letter_key(0'Q, f2).
letter_key(0'R, f3).
letter_key(0'S, f4).

tilde_key(1, home).
tilde_key(2, insert).
tilde_key(3, delete).
tilde_key(4, end).
tilde_key(5, page_up).
tilde_key(6, page_down).
tilde_key(7, home).
tilde_key(8, end).
tilde_key(11, f1).
tilde_key(12, f2).
tilde_key(13, f3).
tilde_key(14, f4).
tilde_key(15, f5).
tilde_key(17, f6).
tilde_key(18, f7).
tilde_key(19, f8).
tilde_key(20, f9).
tilde_key(21, f10).
tilde_key(23, f11).
tilde_key(24, f12).
tilde_key(25, f13).
tilde_key(26, f14).
tilde_key(28, f15).
tilde_key(29, f16).
tilde_key(31, f17).
tilde_key(32, f18).
tilde_key(33, f19).
tilde_key(34, f20).

% Kitty key codes: Unicode code points, plus private-use functional keys.
code_key(9, tab) :- !.
code_key(13, return) :- !.
code_key(27, escape) :- !.
code_key(127, backspace) :- !.
code_key(Code, Key) :-
    between(57376, 57398, Code), !,
    N is Code - 57376 + 13,
    atom_concat(f, N, Key).
code_key(Code, key(Code)) :-
    between(57344, 63743, Code), !.
code_key(Code, Key) :-
    char_code(Key, Code).
