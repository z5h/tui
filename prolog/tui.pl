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
:- reexport(library(tui/loop), [app/4, app/5]).
:- reexport(library(tui/subscriptions), [port_send/2]).


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
%  was, and, for an arrow key no component claimed, as arrived(Direction)
%  where it lands. The cursor moves regardless; what they are rewritten
%  to is handled with the cursor moved. A mouse event bubbles where it
%  happened (see app/5).
%
%  Besides events for update, a component may produce a direction, which
%  moves the cursor one cell, or cursor_by(DX-DY), which moves it by an
%  offset; e.g. to keep the cursor after an edit, or, answering
%  arrived(Direction), on a cell where it belongs. noop takes the event
%  to do nothing: it bubbles no further, and update never sees it.
%
%  @see stack_event_is/3
:- multifile at_event_is/3.
