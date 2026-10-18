:- module(move, []).

/** <module> Move

Pieces dragged with Shift+arrows, the convention for dragging what is
under the cursor. The piece asks to move (Id-Direction); update moves
it, brings it to the front, and moves the cursor along with it.

A piece also sees moved(Direction) when the arrows move the cursor,
from where the cursor was, relative to the piece. So it can tell when
the cursor leaves it.

With the mouse (app/5 option mouse(true)), a piece can be dragged with
the left button. A press moves the cursor to the mouse, and the piece
reports it was grabbed; update notes where on the piece (the cursor
minus the piece's position). Drags the piece does not claim reach update
with their position, and move the grabbed piece to keep that point
under the mouse, until the release.

macOS Terminal.app sends Shift+up and Shift+down as plain up and down
unless configured otherwise (see the README). The app learns which
terminal it runs in from terminal_properties/1, and says so.

    swipl -p library=prolog examples/move.pl
*/

:- use_module(library(tui)).

:- multifile tui:alias_drawable/2.
:- multifile tui:at_event_is/3.

:- initialization(main, main).

main :-
    app((7-7)-model([ piece(a, 5-3, red),
                      piece(b, 20-6, green),
                      piece(c, 35-9, blue) ],
                    "Shift+arrows or the mouse drag a piece", "", none),
        view, update, _, [mouse(true)]).


'#piece'.

piece_size(10-4).

% piece(Id, Color): a box with Id inside, drawn over what is beneath.
tui:alias_drawable(piece(Id, Color),
                   hover([bold], [clear(W-H),
                                  style([fg(Color)], box(W-H, thin)),
                                  2-1-Id])) :-
    piece_size(W-H).

tui:at_event_is(piece(_, _), _-(shift+D), piece-D) :-
    direction(D).
tui:at_event_is(piece(_, _), _-mouse(press, left), piece-grabbed).
tui:at_event_is(piece(_, _), (X-Y)-moved(D), piece-exited) :-
    piece_size(W-H),
    direction_delta(D, DX-DY),
    X1 is X + DX,
    Y1 is Y + DY,
    \+ ( between(0, W, X1), X1 < W,
         between(0, H, Y1), Y1 < H ).

direction_delta(up, 0-(-1)).
direction_delta(down, 0-1).
direction_delta(left, (-1)-0).
direction_delta(right, 1-0).


'#app'.

arena_size(60-18).

view(_-model(Pieces, Status, Note, _),
     column([style([bold], "Move"),
             style([faint], "Arrows move the cursor, Shift+arrows or the mouse drag, q quits"),
             [box(AW-AH, thin) | Drawn],
             Status,
             style([faint], Note)])) :-
    arena_size(AW-AH),
    findall(X1-Y1-(Id : piece(Id, Color)),
            ( member(piece(Id, X-Y, Color), Pieces),
              X1 is X + 1,
              Y1 is Y + 1 ),
            Drawn).

update(q, S, result(S)) :- !.
update(terminal_properties(Ps), C-model(Pieces, Status, _, G), C-model(Pieces, Status, Note, G)) :- !,
    (   memberchk(program('Apple_Terminal'), Ps)
    ->  Note = "Terminal.app: Shift+up/down need a profile setting (see the README)"
    ;   Note = ""
    ).
update(Id-exited, C-model(Pieces, _, Note, G), C-model(Pieces, Status, Note, G)) :- !,
    format(string(Status), "The cursor left ~w", [Id]).
update(Id-grabbed, (CX-CY)-model(Pieces0, _, Note, _), (CX-CY)-model(Pieces, Status, Note, grab(Id, GX-GY))) :-
    selectchk(piece(Id, X-Y, Color), Pieces0, Others), !,
    append(Others, [piece(Id, X-Y, Color)], Pieces),
    GX is CX - X,
    GY is CY - Y,
    format(string(Status), "Grabbed ~w", [Id]).
update((MX-MY)-mouse(drag, left), _-model(Pieces0, _, Note, grab(Id, GX-GY)), (CX-CY)-model(Pieces, Status, Note, grab(Id, GX-GY))) :-
    selectchk(piece(Id, _, Color), Pieces0, Others), !,
    X0 is MX - GX,
    Y0 is MY - GY,
    arena_point_clamped(X0-Y0, X-Y),
    append(Others, [piece(Id, X-Y, Color)], Pieces),
    CX is X + GX,
    CY is Y + GY,
    format(string(Status), "Dragging ~w with the mouse", [Id]).
update(_-mouse(release, _), C-model(Pieces, Status, Note, _), C-model(Pieces, Status, Note, none)) :- !.
update(Id-D, C0-model(Pieces0, _, Note, G), C-model(Pieces, Status, Note, G)) :-
    direction(D),
    selectchk(piece(Id, XY0, Color), Pieces0, Others), !,
    direction_delta(D, DX-DY),
    XY0 = X0-Y0,
    X1 is X0 + DX,
    Y1 is Y0 + DY,
    arena_point_clamped(X1-Y1, XY),
    append(Others, [piece(Id, XY, Color)], Pieces),
    point_from_to_moved(C0, XY0, XY, C),
    format(string(Status), "Dragging ~w ~w", [Id, D]).
update(_, S, S).

% A piece's position (0-0 is the arena's top-left inside corner), moved
% back into the arena if it would leave it.
arena_point_clamped(X0-Y0, X-Y) :-
    arena_size(AW-AH),
    piece_size(PW-PH),
    X is max(0, min(AW - 2 - PW, X0)),
    Y is max(0, min(AH - 2 - PH, Y0)).

% The cursor follows the piece.
point_from_to_moved(X-Y, X0-Y0, X1-Y1, X2-Y2) :-
    X2 is X + X1 - X0,
    Y2 is Y + Y1 - Y0.
