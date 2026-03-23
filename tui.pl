%% TUI — A Text User Interface framework for SWI-Prolog.
%
%  Inspired by TEA (The Elm Architecture). An app is a loop of
%  model → view → event → update. Components are defined via the
%  multifile hooks alias_drawable/2 and at_event_is/3.
%
%  @see app/4 for the main entry point.

:- module(tui,
          [
            op(601, xfy, '.>'),
            op(601, xfy, '.<'),
            op(601, xfy, '.\\/'),
            op(601, xfy, './\\'),
            terminal_size/2,
            wait_for_input/0,
            get_single_input/1,
            input_or_tick/1,
            direction/1,
            stack_event_is/3,
            limits_direction_from_to/4,
            drawable_raw/2,
            drawable//5,
            app/4
          ]).

'#imports'.

:- use_module(one_shot).
:- use_module(library(dcg/basics)).
:- use_module(library(ansi_term)).

%% alias_drawable(+DrawableTerm, -ExpandedDrawable) is semidet.
%
%  Multifile hook. Define custom drawable components by mapping a term
%  to its drawable expansion. During rendering the alias is pushed onto
%  the component stack so that at_event_is/3 can intercept events.
%
%  @see at_event_is/3
:- multifile alias_drawable/2.

%% at_event_is(+AliasOrStack, +RawEvent, -RewrittenEvent) is semidet.
%
%  Multifile hook. Rewrite an event as seen by a component on the alias
%  stack. Called during event bubbling: if the hook succeeds the event
%  is replaced; otherwise bubbling continues to the next stack entry.
%
%  @see stack_event_is/3
:- multifile at_event_is/3.


'#debug'.

:- meta_predicate(log(0)).
log(Goal) :-
    setup_call_cleanup(
        open('tui.log', append, Out),
        with_output_to(Out, Goal),
        close(Out)
    ).

:- op(950, fy, ?).
:- meta_predicate(debug_call(0)).
debug_call(G) :-
    (   G
    *-> log(writeln(pass:G))
    ;   log(writeln(fail:G)), fail
    ).

:- meta_predicate('?'(0)).
'?'(G) :- debug_call(G).

:- op(950, fy, @).
:- meta_predicate('@'(0)).
:- det('@'/1).
'@'(G) :- G.


'#terminal_io'.

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

:- dynamic terminal_size_/2.

% IMPURE: mutable global — caches last-known terminal dimensions.
:- det(set_terminal_size__requires_redraw/3).
set_terminal_size__requires_redraw(Cols, Rows, Redraw) :-
    ignore(terminal_size_(PrevCols, PrevRows)),
    ignore(PrevCols = 0),
    retractall(terminal_size_(_, _)),
    asserta(terminal_size_(Cols, Rows)),
    (  PrevCols-PrevRows = Cols-Rows
    -> Redraw = false
    ;  retractall(location_style_char_(_,_,_)),
       ansi_reset,
       Redraw = true
    ).

%% terminal_size(-Cols, -Rows) is det.
%
%  Current terminal dimensions in columns and rows.
%  Updated automatically on SIGWINCH.
:- det(terminal_size/2).
terminal_size(Cols, Rows) :-
    terminal_size_(Cols, Rows), !.


'#rendering'.

% IMPURE: mutable global — caches what was last written at each screen
% location to avoid redundant terminal writes.
:- dynamic location_style_char_/3.

location_style_char(X-Y, Style, C) :-
    location_style_char_(X-Y, Style, C), !.
location_style_char(X-Y, Style, C) :-
    retractall(location_style_char_(X-Y, _, _)),
    ansi_set_cursor(X, Y),
    ansi_format(Style, '~s', [C]),
    assertz(location_style_char_(X-Y, Style, C)),
    !.

onscreen(X-Y) :-
    X > 0,
    Y > 0,
    terminal_size(Cols, Rows), !,
    X =< Cols,
    Y =< Rows.

raw_attributes_attributes([], []).
raw_attributes_attributes([style_hovergroup(_, false)|T], Attr) :- !,
    raw_attributes_attributes(T, Attr).
raw_attributes_attributes([style_hovergroup(S, true)|T], Attr) :- !,
    append(S, T, ST),
    raw_attributes_attributes(ST, Attr).
raw_attributes_attributes([H|T], [H|A]) :- !,
    raw_attributes_attributes(T, A).

apply_focus(X-Y, Commands) :-
    member((X-Y)-(_-Attr-_), Commands),
    member([style_hovergroup(_S, G)], Attr),
    G = true.
apply_focus(_, _).

render_commands(_, []).
render_commands(Cursor, [((X-Y)-(_-A-C))|T]) :-
    (  onscreen(X-Y)
    -> flatten(A, A1),
       raw_attributes_attributes(A1, A2), !,
       (   Cursor = X-Y
       ->  append(A2, [negative], A3)
       ;   A3 = A2
       ),
       location_style_char(X-Y, A3, C)
    ;  true
    ),
    render_commands(Cursor, T).

%% drawable_raw(+Drawable, -Raw) is det.
%
%  Render Drawable into raw command list wrapped as raw(Commands).
%  Useful for pre-rendering a component for later embedding.
drawable_raw(Drawable, raw(Raw)) :-
    phrase(drawable(Drawable, [], [], 0-0, _), Raw, []).

drawable__normalized_commands__end(Drawables, Deduped, MXY) :-
    call_time(
        phrase(drawable(Drawables, [], [], 1-1, MXY), Commands, []),
        Time
    ),
    !,
    profile_overlay(Time, Commands, Commands1),
    keylist_deduped_prioritize_last(Commands1, Deduped).

profile_overlay(Time, Commands, Commands1) :-
    (   getenv('TUI_PROFILE', _)
    ->  Wall = Time.wall,
        format(atom(Label), '~3fms', [Wall * 1000]),
        atom_chars(Label, Chars),
        profile_chars(Chars, 1, 1, Overlay),
        append(Commands, Overlay, Commands1)
    ;   Commands1 = Commands
    ).

profile_chars([], _, _, []).
profile_chars([C|T], X, Y, [(X-Y)-([]-[bold, fg(yellow), bg(black)]-C)|Rest]) :-
    X1 is X + 1,
    profile_chars(T, X1, Y, Rest).

commands_eventmap([], []).
commands_eventmap([((X-Y)-(S-_-_))|T], EM) :-
    (  onscreen(X-Y)
    -> E = (X-Y)-S,
       EM = [E|EMT]
    ;  EM = EMT
    ),
    commands_eventmap(T, EMT).

pair_key_pred(Delta, K1-_, K2-_) :- compare(Delta, K1, K2).

keylist_deduped_prioritize_last(L0, LN) :-
    reverse(L0, R),
    predsort(pair_key_pred, R, LN).


'#attributes'.

is_stlye_attribute(A) :-
    member(A, [reset,
               bold,
               italic,
               underline,
               negative,
               faint,
               crossed_out]).

is_color_attribute(A) :-
    ( A = fg(Color)
    ; A = bg(Color)
    ; A = hbg(Color)
    ; A = hfg(Color)
    ),
    my_color(Color).

ansi_attribute(A) :- is_stlye_attribute(A).
ansi_attribute(A) :- is_color_attribute(A).

is_attribute(hide_cursor).
is_attribute(style_hovergroup(Style, _G)) :-
    maplist(ansi_attribute, Style).
is_attribute(A) :-
    ansi_attribute(A).

my_color(_).


'#commands'.

%% command(+Command) is semidet.
%
%  True if Command is a valid drawing command.
%  A command is (X-Y)-(Stack-Attrs-Char) where X,Y are integers,
%  Stack is the alias component stack, Attrs is a list of style
%  attributes, and Char is a single-character atom.
:- public(command/1).
command((X-Y)-(Stack-Attrs-C)) :-
    integer(X),
    integer(Y),
    is_list(Attrs),
    is_list(Stack),
    maplist(is_attribute, Attrs),
    atom(C),
    atom_length(C, 1).


'#drawables'.

%% drawable(+Term, +Stack, +Attrs, +XY, -EndXY)// is det.
%
%  DCG that renders a drawable term into a difference list of commands.
%
%  Term is the drawable to render — an atom, string, number, list, or
%  one of the compound drawable terms (see below). Stack is the current
%  alias component stack (used for event routing). Attrs is the current
%  style attribute list. XY is the origin coordinate as X-Y. EndXY is
%  unified with the maximum X-Y coordinate reached.
%
%  Drawable terms:
%    * Atoms, strings, numbers — rendered as character sequences
%    * literal(T)       — render any term as its printed representation
%    * chars(List)      — render a list of characters
%    * raw(Commands)    — embed pre-rendered commands with offset
%    * translate(DX-DY, D) — offset D by DX-DY
%    * X-Y-D            — shorthand for translate(X-Y, D)
%    * port(W-H, D)     — clip D to a W×H viewport
%    * style(Attrs, D)  — push style attributes for D
%    * A .> B           — horizontal concat (A left, B right)
%    * B .< A           — horizontal concat (A rendered first for width)
%    * A .\/ B          — vertical concat (A top, B bottom)
%    * B ./\ A          — vertical concat (A rendered first for height)
%    * [H|T]            — render all drawables overlaid at same origin
%    * Any term matched by alias_drawable/2

:- discontiguous(drawable//5).
:- det(drawable//5).
drawable(Var, _, _, _, _) -->
    { var(Var), !,
      domain_error(drawable, Var)
    }.

drawable(literal(T), Stack, Attr, X-Y, MX-MY) -->
    { atom(T), atom_chars(T, Chars)
    ; string(T), string_chars(T, Chars)
    ; number(T), number_chars(T, Chars)
    ; term_string(T, S), string_chars(S, Chars)
    }, !,
    drawable(chars(Chars), Stack, Attr, X-Y, MX-MY).

drawable(chars([]), _, _, XY, XY) --> !,
    [].

drawable(chars([C|T]), Stack, Attr, X-Y, MX-MY) --> !,
    [ (X-Y)-(Stack-Attr-C)],
    drawable(chars_tail(T), Stack, Attr, X-Y, MX-MY).

drawable(chars_tail([]), _, _, XY, XY) --> !,
    [].

drawable(chars_tail(T), Stack, Attr, X-Y, MX-MY) --> !,
    { NX is X + 1 },
    drawable(chars(T), Stack, Attr, NX-Y, MX-MY), !.

drawable(raw([]), _, _, XY, XY) --> !,
    [].

drawable(raw([H|T]), Stack, Attr, DX-DY, MX-MY) --> !,
    { H = (X-Y)-(StackH-AttrH-C),
      X1 is X + DX,
      Y1 is Y + DY,
      append(AttrH, Attr, Attr1),
      append(StackH, Stack, Stack1),
      H1 = (X1-Y1)-(Stack1-Attr1-C)
    }, !,
    [H1],
    drawable(raw(T), Stack, Attr, DX-DY, MTX-MTY),
    { MX is max(X1, MTX),
      MY is max(Y1, MTY)
    }.

drawable(A, Stack, Attr, X-Y, MX-MY) -->
    { atom(A), atom_chars(A, Chars)
    ; string(A), string_chars(A, Chars)
    ; number(A), number_chars(A, Chars)
    }, !,
    drawable(chars(Chars), Stack, Attr, X-Y, MX-MY).

drawable([H|T], Stack, Attr, XY, MX-MY) --> !,
    drawable(H, Stack, Attr, XY, MX1-MY1),
    drawable(T, Stack, Attr, XY, MX2-MY2),
    { MX is max(MX1, MX2), MY is max(MY1, MY2) }, !.

drawable([], _, _, XY, XY) --> !, [].

:- meta_predicate(capture(//, ?, ?, ?)).
capture(Phrase, C, A, A2) :-
    phrase(Phrase, C, []), !,
    A = A2.

:- meta_predicate(excluding(1, //, ?, ?)).
excluding(Pred, Phrase) -->
    capture(Phrase, C),
    { exclude(Pred, C, E) },
    E.

zone_out(X0-Y0, W-H, X-Y-_) :-
     once(( X < X0
     ; Y < Y0
     ; X >= X0 + W
     ; Y >= Y0 + H
     )).

drawable(translate(TX-TY, Drawables), Stack, Attr, DX-DY, MX-MY) --> !,
    { NDX is DX + TX, NDY is DY + TY },
    drawable(Drawables, Stack, Attr, NDX-NDY, MX-MY).

drawable(TX-TY-Drawable, Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(translate(TX-TY, Drawable), Stack, Attr, DX-DY, MX-MY).

drawable(port(W-H, Drawables), Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(port(W-H, Drawables, _MPX-_MPY), Stack, Attr, DX-DY, MX-MY).

drawable(port(W-H, Drawables, MPX-MPY), Stack, Attr, DX-DY, MX-MY) --> !,
    excluding(zone_out(DX-DY, W-H), drawable(Drawables, Stack, Attr, DX-DY, MPX-MPY)),
    { MX is DX + W - 1, MY is DY + H - 1 }.

drawable(style(Style, Drawables), Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(Drawables, Stack, [Style | Attr ], DX-DY, MX-MY).

drawable(A .> B, Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(A, Stack, Attr, DX-DY, AMX-AMY),
    { WidthA is AMX - DX + 1 },
    drawable(translate(WidthA-0, B), Stack, Attr, DX-DY, BMX-BMY),
    { MX is max(AMX, BMX), MY is max(AMY, BMY) }.

drawable(B .< A, Stack, Attr, DX-DY, MX-MY) --> !,
    { phrase(drawable(A, Stack, Attr, DX-DY, AMX-AMY), Raw, []),
      WidthA is AMX - DX + 1
    },
    drawable(translate(WidthA-0, B), Stack, Attr, DX-DY, BMX-BMY),
    drawable(raw(Raw), [], [], 0-0, _-_),
    { MX is max(AMX, BMX), MY is max(AMY, BMY) }.

drawable(A .\/ B, Stack, Attr, DX-DY, MX-MY) --> !,
    drawable(A, Stack, Attr, DX-DY, AMX-AMY),
    { HeightA is AMY - DY + 1 },
    drawable(translate(0-HeightA, B), Stack, Attr, DX-DY, BMX-BMY),
    { MX is max(AMX, BMX), MY is max(AMY, BMY) }.

drawable(B ./\ A, Stack, Attr, DX-DY, MX-MY) --> !,
    { phrase(drawable(A, Stack, Attr, DX-DY, AMX-AMY), Raw, []),
      HeightA is AMY - DY + 1
    },
    drawable(translate(0-HeightA, B), Stack, Attr, DX-DY, BMX-BMY),
    drawable(raw(Raw), [], [], 0-0, _-_),
    { MX is max(AMX, BMX), MY is max(AMY, BMY) }.

drawable(A, Stack, Attr, DX-DY, MX-MY) -->
    { tui:alias_drawable(A, D) }, !,
    drawable(D, [A | Stack], Attr, DX-DY, MX-MY).

drawable(D, _, _, _, _) -->
    { domain_error(drawable, D) }.


'#builtin_components'.

% Error guard for uninstantiated alias lookups.
alias_drawable(V, _) :-
    var(V), !,
    instantiation_error(alias_drawable).

%% alias_drawable(hover(+Style, +Term), -Drawable).
%
%  Wrap Term with a hover highlight. When the cursor is over this
%  component, Style attributes are applied.
alias_drawable(hover(Style, Term), HoverTerm) :-
    HoverTerm = style([style_hovergroup(Style, _G)], Term).

%% alias_drawable(+X-+Y-+Term, -Drawable).
%
%  Shorthand for translate(X-Y, Term). Matches only when X and Y are
%  integers and Term is a compound (not another pair).
alias_drawable(X-Y-Term, translate(X-Y, Term)) :-
    integer(X), integer(Y),
    functor(Term, Name, Arity),
    Name \= '-',
    Arity > 0, !.

%% alias_drawable(box(+W-+H, +Style), -Drawable).
%
%  A W×H box border in the given Style (thin, thick, or double).
%  The box is hollow — only the border characters are drawn.
alias_drawable(box(W0-H0, Style), [Top, Bottom, Left, Right, Corners]) :-
    W is W0 - 1,
    H is H0 - 1,
    style_corner_char(Style, tl, TL),
    style_corner_char(Style, tr, TR),
    style_corner_char(Style, bl, BL),
    style_corner_char(Style, br, BR),
    style_horizontal(Style, Hoz),
    style_vertical(Style, Vrt),
    Corners = [(0-0)-TL, (W-0)-TR, (0-H)-BL, (W-H)-BR],
    WM is W - 1,
    HM is H - 1,
    char_from_to_line(Hoz, 1-0, WM-0, Top),
    char_from_to_line(Hoz, 1-H, WM-H, Bottom),
    char_from_to_line(Vrt, 0-1, 0-HM, Left),
    char_from_to_line(Vrt, W-1, W-HM, Right).

%% alias_drawable(clear(+W-+H), -Drawable).
%
%  A W×H rectangle of spaces with reset styling. Used to erase a
%  region before drawing over it.
alias_drawable(clear(W-H), style([reset, bg(default)], Spaces)) :-
    findall((X-Y)-' ',
            ( between(0, W, X),
              between(0, H, Y) ),
            Spaces).

% Line and box-drawing character tables.

char_from_to_line(C, X1-Y, X2-Y, L) :- !,
    (  X1 > X2
    -> From = X2, To = X1
    ;  From = X1, To = X2
    ),
    findall((X-Y)-C, between(From, To, X), L).
char_from_to_line(C, X-Y1, X-Y2, L) :- !,
    (  Y1 > Y2
    -> From = Y2, To = Y1
    ;  From = Y1, To = Y2
    ),
    findall((X-Y)-C, between(From, To, Y), L).

:- discontiguous style_corner_char/3.
:- discontiguous style_horizontal/2.
:- discontiguous style_vertical/2.

style_corner_char(thick, tl, '\u250f').
style_corner_char(thick, bl, '\u2517').
style_corner_char(thick, tr, '\u2513').
style_corner_char(thick, br, '\u251b').
style_horizontal(thick, '\u2501').
style_vertical(thick, '\u2503').

style_corner_char(thin, tl, '\u250c').
style_corner_char(thin, bl, '\u2514').
style_corner_char(thin, tr, '\u2510').
style_corner_char(thin, br, '\u2518').
style_horizontal(thin, '\u2500').
style_vertical(thin, '\u2502').

style_corner_char(double, tl, '\u2554').
style_corner_char(double, tr, '\u2557').
style_corner_char(double, bl, '\u255a').
style_corner_char(double, br, '\u255d').
style_horizontal(double, '\u2550').
style_vertical(double, '\u2551').


'#app'.

:- det(tui_init/0).
tui_init :-
    ansi_reset,
    ansi_hide_cursor,
    retractall(location_style_char_(_, _, _)),
    retractall(terminal_size_(_, _)),
    tty_request_size,
    wait_for_terminal_size.

wait_for_terminal_size :-
    get_single_input(In),
    (  In = terminal_size(Cols, Rows)
    -> set_terminal_size__requires_redraw(Cols, Rows, _)
    ;  wait_for_terminal_size
    ).

%% app(+State, :View, :Update, -Result) is det.
%
%  Run a TUI application. State is the initial (CursorX-CursorY)-Model.
%  View is called as call(View, State, Drawable) to produce the current
%  view. Update is called as call(Update, Event, State0, State1) to
%  handle events. Result is unified when Update produces result(R).
%
%  Three threads cooperate:
%    * Main thread — owns TTY, reads input, dispatches events
%    * tty_output  — serializes terminal writes
%    * update      — processes events, calls Update, generates views
%
%  The app exits when update/3 returns result(R) for some event.
:- meta_predicate(app(?, 2, 3, ?)).
app(State, View, Update, Result) :-
    one_shot_message(FinalUpdate, FinalUpdateInput),
    call_cleanup(
        with_tty_raw(
            (
                tui_init,
                thread_self(MainThread),
                thread_create(tty_output_loop, _, [alias(tty_output)]),
                on_signal(winch, _, sig_winch),
                thread_create(
                    update_loop(State, _, _, View, Update, FinalUpdate),
                    _UpdateId,
                    [alias(update)]
                ),
                needs_repaint,
                input_loop(MainThread, FinalUpdateInput, Result)
            )
        ),
        (
            @ ignore(thread_send_message(tty_output, exit)),
            @ on_signal(winch, _, default),
            @ ansi_reset,
            @ ansi_show_cursor
        )
    ).

sig_winch(_) :-
    tty_request_size.


'#threads'.

% Architecture:
%
%   ┌─────────────────────────────────────────────────────────────┐
%   │                     EVENT SOURCES                           │
%   ├─────────────────┬─────────────────┬─────────────────────────┤
%   │  Main Thread    │  Signal Handler │  Other Async Sources    │
%   │  (TTY input)    │  (SIGWINCH)     │  (timers, network, etc) │
%   └────────┬────────┴────────┬────────┴────────────┬────────────┘
%            │                 │                     │
%            │    thread_send_message(update, ...)   │
%            └─────────────────┼─────────────────────┘
%                              ▼
%                     ┌─────────────────┐
%                     │  Update Thread  │
%                     │  - process event│
%                     │  - update state │
%                     │  - generate view│
%                     └────────┬────────┘
%                              │
%                              │ thread_send_message(tty_output, render(...))
%                              ▼
%                     ┌─────────────────┐
%                     │  TTY Output     │
%                     │  - render       │
%                     └─────────────────┘

% --- Main Thread: Input Loop ---
% Runs in the main thread which owns the TTY.
% Monitors both user_input and the one-shot pipe for app termination.

input_loop(MainThread, FinalUpdateInput, Result) :-
        wait_for_input([user_input, FinalUpdateInput], Ready, infinite),
        (   Ready = [user_input]
        ->  get_single_input(In),
            handle_input(In),
            input_loop(MainThread, FinalUpdateInput, Result)
        ;   @ read_term(FinalUpdateInput, Result, []),
            @ close(FinalUpdateInput)
        ).

handle_input(terminal_size(Cols, Rows)) :- !,
    set_terminal_size__requires_redraw(Cols, Rows, Redraw),
    (   Redraw
    ->  needs_repaint
    ;   true
    ).
handle_input(In) :-
    thread_send_message(update, update(In)).

% --- TTY Output Thread ---
% Serializes all terminal output to avoid interleaving from multiple threads.

tty_output_loop :-
    thread_get_message(tty_output, M),
    (   M = exit
    ->  true

    ;   M = tty_render(Cursor, Commands)
    ->  tty_render(Cursor, Commands),
        tty_output_loop

    ;   M = tty_request_size
    ->  tty_request_size,
        tty_output_loop
    ;   assertion((fail, message:M))
    ).

tty_render(X-Y, Commands) :-
    ansi_hide_cursor,
    render_commands(X-Y, Commands),
    flush_output.

tty_request_size :-
    flush_output,
    ansi_save_cursor,
    ansi_set_cursor(1000, 1000),
    ansi_csi("6n"),
    ansi_restore_cursor,
    flush_output.

% --- Update Thread ---
% Processes events, updates state, generates views.

render(State, View, Commands, EventAssoc, EX-EY) :-
    (X-Y)-_ = State,
    call(View, State, Drawable),
    drawable__normalized_commands__end(Drawable, Commands, EX-EY),
    once(apply_focus(X-Y, Commands)),
    thread_send_message(tty_output, tty_render(X-Y, Commands)),
    commands_eventmap(Commands, EventMap),
    list_to_assoc(EventMap, EventAssoc).

needs_repaint :-
    thread_send_message(update, view).

handle_new_state(State1, View, Update, FinalUpdate) :-
    needs_repaint,
    update_loop(State1, _, _, View, Update, FinalUpdate).

thread_get_message_prioritize(Thread, M, P) :-
    (   thread_peek_message(Thread, P)
    ->  M = P
    ;   true
    ),
    thread_get_message(Thread, M).

:- meta_predicate update_loop(+, ?, ?, 2, 3, +).
update_loop(State0, EventAssoc, EX-EY, View, Update, FinalUpdate) :-
    thread_get_message_prioritize(update, M, view),

    (   M = view
    ->  render(State0, View, _Commands, NewEventAssoc, EX1-EY1),
        update_loop(State0, NewEventAssoc, EX1-EY1, View, Update, FinalUpdate)

    ;   M = update(E0)
    ->  (X-Y)-Model0 = State0,

        assertion(ground(EX)),
        assertion(ground(EY)),  % Guard: need valid extents
        state_event_assoc_bubbled(State0, E0, EventAssoc, E1),
        (   E1 = result(Result)
        ->  FinalUpdate = Result,
            thread_exit(_)

            % Direction keys: handle cursor movement
        ;   direction(E1)
        ->  limits_direction_from_to(EX-EY, E1, X-Y, NX-NY),
            (   X-Y = NX-NY
            ->  % No change, just re-loop
                update_loop(State0, EventAssoc, EX-EY, View, Update, FinalUpdate)

            ;   state_event_assoc_bubbled(State0, moved(E1, X-Y, NX-NY), EventAssoc, E2),
                (   E2 = moved(E1, X-Y, NX-NY)
                ->  handle_new_state((NX-NY)-Model0, View, Update, FinalUpdate)

                ;   call(Update, E2, (NX-NY)-Model0, State1),
                    handle_new_state(State1, View, Update, FinalUpdate)
                )
            )

        ;   % Normal event: call update and check result
            call(Update, E1, State0, State1),
            handle_new_state(State1, View, Update, FinalUpdate)
        )

    ;   assertion((fail, message:M))
    ).

:- public(repeat/1).
repeat(Goal) :-
    repeat,
    copy_term(Goal, Copy),
    call(Copy),
    Goal = Copy.

:- public(no_repeat/1).
no_repeat(Goal) :- Goal.


'#events'.

%% stack_event_is(+Stack, +RawEvent, -BubbledEvent) is det.
%
%  Walk the component Stack from innermost to outermost, giving each
%  component a chance to rewrite the event via at_event_is/3. If no
%  component rewrites the event, BubbledEvent = RawEvent.
stack_event_is(V, _, _) :- var(V), domain_error(stack_event_is, stack:V).
stack_event_is(_, V, _) :- var(V), domain_error(stack_event_is, event:V).
stack_event_is([H|T], E, Is) :- !,
    (  tui:at_event_is(H, E, Next)
    -> stack_event_is([H|T], Next, Is)
    ;  stack_event_is(T, E, Is)
    ).
stack_event_is([], E, Is) :- !,
    (  tui:at_event_is([], E, Next)
    -> stack_event_is([], Next, Is)
    ;  Is = E
    ).

state_event_assoc_bubbled(S0, E0, EventAssoc, E1) :-
    (X-Y)-_ = S0,
    (  get_assoc(X-Y, EventAssoc, Stack)
    -> true
    ;  Stack = []
    ),
    stack_event_is(Stack, E0, E1).


'#input'.

%% wait_for_input is det.
%
%  Block until a single input event is available, then discard it.
wait_for_input :-
    get_single_input(_).

%% get_single_input(-Event) is semidet.
%
%  Read one input event from the terminal. Handles escape sequences
%  (arrow keys, function keys, etc.) and control characters. Event
%  is an atom like up, down, return, tab, or a single character atom
%  for printable keys. Blocks until input is available.
get_single_input(I) :-
    get_single_input(I, true).

get_single_input(I, Wait) :-
    (  Wait = false
    -> wait_for_input([user_input], [user_input], 0),
       get_single_char(H)
    ;  get_single_char(H)
    ),
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

%% input_or_tick(-Event) is det.
%
%  Non-blocking input with a tick fallback. If input is available
%  within the tick interval, returns the input event. Otherwise
%  returns time-TimeAtom where TimeAtom is the formatted current time.
:- dynamic(last_tick/1).
input_or_tick(E) :-
    ( last_tick(Last), ! ; Last = 0 ),
    get_time(Now),
    (  Now - Last < 1, get_single_input(E, false)
    -> true
    ;  retractall(last_tick(_)),
       assertz(last_tick(Now)),
       E = time-T,
       sleep(0),
       format_time(atom(T), '%T', Now)
    ).

no_input :-
   \+ wait_for_input([user_input], [user_input], 0).

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


'#navigation'.

%% direction(+Event) is semidet.
%
%  True if Event is a directional input: up, down, left, or right.
direction(E) :- member(E, [up, down, left, right]).

%% limits_direction_from_to(+Limits, +Direction, +From, -To) is det.
%
%  Compute the cursor position To by moving one step in Direction from
%  From, clamped to 1..Limits. Limits is MaxX-MaxY.
limits_direction_from_to(_-_, up, X-Y0, X-Y) :-
    Y is max(1, Y0 - 1).
limits_direction_from_to(_-_, left, X0-Y, X-Y) :-
    X is max(1, X0 - 1).
limits_direction_from_to(MX-_, right, X0-Y, X-Y) :-
    X is min(MX, X0 + 1).
limits_direction_from_to(_-MY, down, X-Y0, X-Y) :-
    Y is min(MY, Y0 + 1).
