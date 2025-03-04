:- module(example, [go/0
                   ]).

:- use_module(tui).

go :- step_app(init, step, view).

view(xywh(X,Y,W,H), Rs) :-
    findall(Re,
            (between(1, W, C),
             between(1, H, R),
             render(C,R, xywh(X,Y,W,H), Re)
            ),
            Rs
           ).

render(X,Y, xywh(X,Y,W,H), X:Y:red:white:"@") :- !.
render(C,R, xywh(X,Y,W,H), C:R:red:"+") :-
    \+ (C = X, R = Y).


init(xywh(1,1,70,30)).

step(left,  xywh(1,Y,W,H), xywh(1,Y,W,H)) :- !.
step(right, xywh(W,Y,W,H), xywh(W,Y,W,H)) :- !.

step(left,  xywh(X,Y,W,H), xywh(X1,Y,W,H)) :- !,
    X1 is X - 1.
step(right, xywh(X,Y,W,H), xywh(X1,Y,W,H)) :- !,
    X1 is X + 1.

step(up,    xywh(X,1,W,H), xywh(X,1,W,H)) :- !.
step(down,  xywh(X,H,W,H), xywh(X,H,W,H)) :- !.

step(up,    xywh(X,Y,W,H), xywh(X,Y1,W,H)) :- !,
    Y1 is Y - 1.
step(down,  xywh(X,Y,W,H), xywh(X,Y1,W,H)) :- !,
    Y1 is Y + 1.


