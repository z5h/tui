:- module(tui_hover,
          [
            apply_focus/2,
            raw_attributes_attributes/2
          ]).

/** <module> Hover

Styling that applies when the cursor is over a component. Every cell of
one hover/2 instance shares an unbound group variable; binding it to
true under the cursor turns the hover style on for the whole group.
*/

:- use_module(library(tui/utils)).

:- multifile tui:alias_drawable/2.


'#component'.

%!  hover(+Style, +Term)
%
%  Wrap Term with a hover highlight. When the cursor is over this
%  component, Style attributes are applied.
tui:alias_drawable(hover(Style, Term), hover(Style, Term, _Group)).

tui:alias_drawable(hover(Style, Term, Group), HoverTerm) :-
    HoverTerm = style([style_hovergroup(Style, Group)], Term).


'#focus'.

%!  apply_focus(+Cursor, +Commands) is det.
%
%  Binds the group of every hover on the stack under Cursor, X-Y, to
%  true, turning their styles on.
apply_focus(X-Y, Commands) :-
    member((X-Y)-(Stack-Attr-_), Commands),
    member([style_hovergroup(_S, G)], Attr),
    stack_focused(Stack),
    G = true.
apply_focus(_, _).

:- det(stack_focused/1).
stack_focused([]).
stack_focused([_-hover(_,_,true) | Tail ]) :- !,
    stack_focused(Tail).
stack_focused([_ | Tail]) :-
    stack_focused(Tail).

%!  raw_attributes_attributes(+Raw, -Attrs) is det.
%
%  Attrs is Raw with each hover group replaced by its style when on, and
%  dropped when off. Groups still unbound are off.
raw_attributes_attributes([], []).
raw_attributes_attributes([style_hovergroup(_, false)|T], Attr) :- !,
    raw_attributes_attributes(T, Attr).
raw_attributes_attributes([style_hovergroup(S, true)|T], Attr) :- !,
    append(S, T, ST),
    raw_attributes_attributes(ST, Attr).
raw_attributes_attributes([H|T], [H|A]) :- !,
    raw_attributes_attributes(T, A).
