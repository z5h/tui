:- module(tui_utils,
          [
              mapindexed/3
          ]).

%!  mapindexed(:Goal, +List, -Mapped) is det.
%
%  Like maplist/3 but calls Goal with a 1-based index:
%  call(Goal, Index, Element, MappedElement) for each element.
:- meta_predicate mapindexed(3, ?, ?).
mapindexed(F, List, Mapped) :-
    function_list_from_mapped(F, List, 1, Mapped).

:- meta_predicate function_list_from_mapped(3, ?, ?, ?).
function_list_from_mapped(_, [], _, []).
function_list_from_mapped(F, [H  |T], I, [MH  |MT]) :-
    call(F, I, H, MH),
    J is I + 1,
    function_list_from_mapped(F, T, J, MT).
