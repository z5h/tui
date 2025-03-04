:- module(tui, [step_app/3
                , wait/0
                , log/1
                , draw_tui/1
                , draw_over/2
                , draw/1
                , prev_new_updates/3
               ]).

:- use_module(library(ansi_termx)).
:- use_module(local(core/core)).

/*
This will be a Prolog Terminal UI (TUI) library.
It's going to be based on the rendering phase of The Elm Architecture (TEA), or the idea of pure React functions.
Broadly speaking, to render to terminal we take a description of the view, render it into an intermediate prepresentation that we can diff with the previous to see what parts of the terminal actually need updating, then we update.

The things we can render (TUI primitives) are:
VIEWPORT: acountainer with a width and height, containing a SCENE.
A viewport has an x/y position, ( along with it's width/height), which determines what part of the scene is rendered in the viewport.
SCENE: a scene's height and width is determined by it's contents. It may contain, at given coordinates, ROW, COL, TEXT, VIEWPORT elements.
TEXT: decorated/undecorated is always rendered horizontally, and newlines are ignored. (users must manually transform text into a COL of TEXT if desired)
COL: lays out contents top to bottom, so entries don't need coordinates.
ROW:  lays out contents left to right, so entries don't need coordinates.

We'll use SWI-Prolog and the ansi_termx library to implement.
Docs are here https://www.swi-prolog.org/pack/file_details/ansi_termx/prolog/ansi_termx.pl

*/

:- dynamic log_/1.

log(Val) :-
    log_(nolog)
        ->
        true
        ;
        assertz(log_(Val)).


loglines([[], ['Log:'] | Lines]) :-
    findall(Line, log_(Line), Lines).

draw_tui(Lines) :-
    with_tty_raw(
        ( clear_screen,
          cursor_position(Row, Col),
          render_view(Lines, Row, Col)
        )).

draw_over((Row, Col), Line) :-
    with_tty_raw(
        ( cursor_position(R0, C0),
          render_line(Line, Row, Col),
          cursor_position(R0, C0)
        )).

:- meta_predicate(step_app(1,3,2)).
step_app(Initialize, Step, View) :-
    retractall(log_(_)),
    ./ call(Initialize,State0),
    with_tty_raw(
        (clear_screen, model_step_view_prev(State0, Step, View, []) , reset)
    ).

prev_new_updates([], [], []).

prev_new_updates([], [X:Y:N | New], [X:Y:([]-N) | Updates]) :-
    prev_new_updates([], New, Updates).

prev_new_updates([X:Y:(_-_) | Prev], [], [X:Y:([]-(white:' ')) | Updates]) :-
    prev_new_updates(Prev, [], Updates).


prev_new_updates([X:Y:(_-P)|Prev], [X:Y:N|New], [X:Y:(P-N) | Updates]) :- !,
    prev_new_updates(Prev, New, Updates).

prev_new_updates([X1:Y1:(_-P)|Prev], [X2:Y2:N|New], [U|Updates]) :-
    compare(Comp, X1:Y1, X2:Y2),
    (  Comp = '<'
    -> U =  X1:Y1:(P-(white:' ')),
       prev_new_updates(Prev, [X2:Y2:N|New], Updates)

    ;  Comp = '>',
       U = X2:Y2:([]-N),
       prev_new_updates([X1:Y1:(_-P)|Prev], New, Updates)
    ).

term_chars(T,[T]) :-
    atom(T), atom_length(T, 1), !.

term_chars(T, C) :-
    format(string(S), "~w", [T]),
    string_chars(S, C).


draw_normalized_(X:Y:C:B:[], []).
draw_normalized_(X:Y:C:B:[Char|Rest], [X:Y:C:B:Char | MRest]) :-
    Next is X + 1,
    draw_normalized_(Next:Y:C:B:Rest, MRest).


draw_normalized(X:Y:C:B:W, Normalized) :- !,
    ./ term_chars(W, Chars),
    ./ draw_normalized_(X:Y:C:B:Chars, Normalized).

draw_normalized(X:Y:C:W, Normalized) :- !,
    ./ draw_normalized(X:Y:C:default:W, Normalized).

raw_normalized(R, N) :-
    ./ maplist(draw_normalized, R, N1),
    ./ flatten(N1, F),
    ./ sort(F, N).


:- meta_predicate(model_step_view_prev(+,3,2,+)).
model_step_view_prev(Model, Step, View, Prev) :-
    ./ call(View, Model, Draw),
    raw_normalized(Draw, Normalized),

    ./ prev_new_updates(Prev, Normalized, Updates),
    draw(Updates),
    cursor_position(9999,9999),
    %loglines(LogLines),
    %retractall(log_(_)),
    %cursor_position(Row, Col),
    %append(ViewLines, LogLines, AllLines),
    %render_view(AllLines, Row, Col),nl,

    get_single_char(C), !,

    (  action(C, Action)
    -> ./ call(Step, Action, Model, Model1),
       model_step_view_prev(Model1, Step, View, Updates)

    ;  c(C)
    -> clear_screen,
       model_step_view_prev(Model, Step, View, [])
    ;  q(C)
    -> true
    ;  model_step_view_prev(Model, Step, View, Updates)
    ).


wait :-
    get_single_char(_).

draw([]).
draw([_:_:(Prev-Prev) | Draw]) :- !,
    draw(Draw).

draw([X:Y:(_-(Color:Back:Word)) | Draw]) :- !,
    cursor_position(Y,X),
    color(Color, Back, [bold], Word, Output),
    format("~w", [Output]),
    draw(Draw).

draw([X:Y:(_-(Color:Word)) | Draw]) :-
    cursor_position(Y,X),
    color(Color, default, [bold], Word, Output),
    format("~w", [Output]),
    draw(Draw).



render_view([], _, _).
render_view([Line|Lines], Row, Col) :-
    render_line(Line, Row, Col),
    render_view(Lines, _, Col).

render_line([], _, _) :-
    cursor_position(Row, _),
    NewRow is Row + 1,
    cursor_position(NewRow, 1).

render_line([color:Color:Word | Words], Row, Col) :-
    !,
    cursor_position(Row, Col),
    color(Color, default, [], Word, Output),
    format("~w", [Output]),
    cursor_position(Row, NewCol),
    render_line(Words, Row, NewCol).

render_line([Word | Words], Row, Col) :-
    cursor_position(Row, Col),
    format("~w", [Word]),
    cursor_position(Row, NewCol),
    render_line(Words, Row, NewCol).

echo_keys :-
    with_tty_raw((clear_screen, echo_loop)).

% ASCII code for q
q(113).
c(99).

dir(65, up).
dir(66, down).
dir(67, right).
dir(68, left).

action(K,A) :- dir(K, A).
action(122, a). %z
action(120, b). %x

cursor_restore :- cursor_unsave.

echo_loop :-
    get_single_char(C),
    (dir(C,D) -> cursor_move(1, D), cursor_save; true),
    (   q(C)  % ASCII code for q
    ->  !,
        clear_screen,
        halt
        ;
        cursor_save,
        cursor_position(1,1),
        write_canonical(C),  % print the character code
        write('   '),
        cursor_restore,
        echo_loop     % continue the loop
    ).














