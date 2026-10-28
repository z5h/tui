:- module(tui_hover,
          [
            apply_focus/2,
            raw_attributes_attributes/2
          ]).

/** <module> Hover

Styling that applies when the cursor is over a component: the core
aliases `hover(Style, Term)`, `hover(Style, Term, Group)` and
`unhovered(Style, Term, Group)`. They are documented under
tui:alias_drawable/2. This module is internal.

Every cell of
one hover/2 instance shares an unbound group variable; binding it to
true under the cursor turns the hover style on for the whole group.
*/

:- use_module(library(tui/utils)).

:- multifile tui:alias_drawable/2.


'#component'.

/*<tui> hover(Style, Term)
Draws Term, with the attributes Style added while the cursor is on it.
*/
tui:alias_drawable(hover(Style, Term), hover(Style, Term, _Group)).

/*<tui> hover(Style, Term, Group)
As `hover(Style, Term)`, in the hover group Group: an unbound variable
that hovers sharing it turn on together, when the cursor is over any of
them. For example, a button whose end caps change shape on focus:

```
tui:alias_drawable(button(Text), hover([negative], Content, G)) :-
    Content = hover([char('▌')], '┃', G) .> Text
           .> hover([char('▐')], '┃', G).
```
*/
tui:alias_drawable(hover(Style, Term, Group), HoverTerm) :-
    HoverTerm = style([style_hovergroup(Style, Group)], Term).

/*<tui> unhovered(Style, Term, Group)
The other state of `hover(Style, Term, Group)`: Style applies while
Group is off, and is dropped when the cursor turns it on. For example, a
field underlined except when focused, where it is negative:

```
hover([negative], unhovered([underline], Field, G), G)
```
*/
tui:alias_drawable(unhovered(Style, Term, Group), UnhoveredTerm) :-
    UnhoveredTerm = style([style_unhovergroup(Style, Group)], Term).


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
%  dropped when off; an unhovered group the other way round. Groups still
%  unbound are off.
raw_attributes_attributes([], []).
raw_attributes_attributes([style_hovergroup(_, false)|T], Attr) :- !,
    raw_attributes_attributes(T, Attr).
raw_attributes_attributes([style_hovergroup(S, true)|T], Attr) :- !,
    append(S, T, ST),
    raw_attributes_attributes(ST, Attr).
raw_attributes_attributes([style_unhovergroup(S, false)|T], Attr) :- !,
    append(S, T, ST),
    raw_attributes_attributes(ST, Attr).
raw_attributes_attributes([style_unhovergroup(_, true)|T], Attr) :- !,
    raw_attributes_attributes(T, Attr).
raw_attributes_attributes([H|T], [H|A]) :- !,
    raw_attributes_attributes(T, A).
