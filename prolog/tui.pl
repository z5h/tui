:- module(tui,
          [
            op(601, xfy, '.>'),
            op(601, xfy, '.<'),
            op(601, xfy, '.\\/'),
            op(601, xfy, './\\')
          ]).

/** <module> Text User Interface framework

A TUI framework for SWI-Prolog, inspired by TEA (The Elm Architecture).
Components are defined via the multifile hooks alias_drawable/2 and
at_event_is/3.

This module gives the event loop and the core drawables. Ready-made,
styled components are opt-in: load library(tui/components).

@author Mark Bolusmjak
@see app/4
*/

'#imports'.

:- reexport(library(tui/utils), [direction/1, limits_direction_from_to/4]).
:- reexport(library(tui/drawable), [drawable//5, drawable_raw/2]).
:- reexport(library(tui/events), [stack_event_is/3]).
:- reexport(library(tui/loop), [app/4]).


'#hooks'.

%!  alias_drawable(+DrawableTerm, -ExpandedDrawable) is semidet.
%
%  Multifile hook. Define custom drawable components by mapping a term
%  to its drawable expansion. During rendering the alias is pushed onto
%  the component stack so that at_event_is/3 can intercept events.
%
%  @see at_event_is/3
:- multifile alias_drawable/2.

%!  at_event_is(+AliasOrStack, +X-Y-RawEvent, -RewrittenEvent) is nondet.
%
%  Multifile hook. Rewrite an event as seen by a component on the alias
%  stack. X-Y is where the event happened, relative to the component's
%  origin (absolute for [], the bottom of the stack; with no cursor, []
%  sees RawEvent alone). Called during event bubbling: each solution
%  replaces the event, and bubbles on from the same component; with
%  none, bubbling continues to the next stack entry. Every event the
%  raw event becomes reaches update, in order.
%
%  A cursor movement bubbles as moved(Direction) from where the cursor
%  was. The cursor moves regardless; what moved(Direction) is rewritten
%  to reaches update with the cursor moved.
%
%  @see stack_event_is/3
:- multifile at_event_is/3.
