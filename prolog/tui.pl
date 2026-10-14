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

@author Mark Bolusmjak
@see app/4
*/

'#imports'.

:- reexport(library(tui/utils), [direction/1, limits_direction_from_to/4]).
:- reexport(library(tui/drawable), [drawable//5, drawable_raw/2]).
:- reexport(library(tui/events), [stack_event_is/3]).
:- reexport(library(tui/loop), [app/4]).
:- use_module(library(tui/components)).


'#hooks'.

%!  alias_drawable(+DrawableTerm, -ExpandedDrawable) is semidet.
%
%  Multifile hook. Define custom drawable components by mapping a term
%  to its drawable expansion. During rendering the alias is pushed onto
%  the component stack so that at_event_is/3 can intercept events.
%
%  @see at_event_is/3
:- multifile alias_drawable/2.

%!  at_event_is(+AliasOrStack, +RawEvent, -RewrittenEvent) is semidet.
%
%  Multifile hook. Rewrite an event as seen by a component on the alias
%  stack. Called during event bubbling: if the hook succeeds the event
%  is replaced; otherwise bubbling continues to the next stack entry.
%
%  @see stack_event_is/3
:- multifile at_event_is/3.
