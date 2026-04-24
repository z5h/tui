:- module(tui_assocs, [ empty_assocs/1,
                    empty_assocs//0,
                    assocs_pair/2,
                    assocs_pairs/2,
                    pair_pair_assocs_assocs/4,
                    assocs_pair_assocs/3
                  ]).

/** <module> Lightweight association lists

A simple alternative to library(assoc) AVL trees. Associations are
plain lists of Key-Value pairs, which allows direct pattern matching
via assocs_pairs/2. Suitable for small collections where the
simplicity of list operations outweighs AVL lookup performance.
*/


'#construction'.

%!  empty_assocs(-Assocs) is det.
%
%  Assocs is an empty association list.
empty_assocs([]).

%!  empty_assocs// is det.
%
%  DCG variant — threads an empty association list through state.
empty_assocs -->
    state([]).

state(S, S, S).
state(S0, S, S0, S).


'#query'.

%!  assocs_pair(+Assocs, ?Key-?Value) is nondet.
%
%  True when Key-Value is a pair in Assocs. Enumerates all pairs
%  on backtracking.
assocs_pair([ K-V  |_ ], K-V).
assocs_pair([ _  |T ], K-V) :-
    assocs_pair(T, K-V).

%!  assocs_pairs(+Assocs, +Pairs) is semidet.
%
%  True when every pair in Pairs can be found in Assocs.
%  Pairs is a list of Key-Value terms; each is looked up independently.
assocs_pairs(_, []).
assocs_pairs(A, [P|T]) :-
    assocs_pair(A, P),
    assocs_pairs(A, T).


'#update'.

%!  assocs_pair_assocs(?Assocs0, +Key-+Value, ?Assocs1) is nondet.
%
%  Assocs1 is Assocs0 with Key-Value added at the front. Can also
%  be used to decompose: if Assocs1 is known, extracts Key-Value
%  and the remaining Assocs0.
assocs_pair_assocs(T, K-V, [K-V|T]).
assocs_pair_assocs([H  |T], K-V, [H|T2]) :-
    assocs_pair_assocs(T, K-V, T2).

%!  pair_pair_assocs_assocs(+Old, +New, +Assocs0, -Assocs1) is det.
%
%  Replace the pair matching Old with New in Assocs0, producing
%  Assocs1. Old is Key0-Value0, New is Key1-Value1. The pair
%  matching Old is removed and New is inserted.
pair_pair_assocs_assocs(K0-V0, K1-V1, A0, A1) :-
    assocs_pair_assocs(A, K0-V0, A0),
    assocs_pair_assocs(A, K1-V1, A1).

%!  assocs_pair_removed(+Assocs, +Key-?Value, -Rest) is nondet.
%
%  Rest is Assocs with the first occurrence of Key-Value removed.
assocs_pair_removed([], _, []).
assocs_pair_removed([HK-HV|T], K-V, [HK-HV|R]) :-
    dif(HK, K),
    assocs_pair_removed(T, K-V, R).
assocs_pair_removed([K-V|R], K-V, R).
