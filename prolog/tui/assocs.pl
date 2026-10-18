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
%  Pairs is a list of Key-Value terms with ground keys; each is looked
%  up independently, by the first pair in Assocs with its key.
assocs_pairs(_, []).
assocs_pairs(A, [K-V|T]) :-
    assocs_key_value(A, K, V),
    assocs_pairs(A, T).

% The value of the first pair with key K (ground).
assocs_key_value([K0-V0|T], K, V) :-
    (   K0 == K
    ->  V = V0
    ;   assocs_key_value(T, K, V)
    ).


'#update'.

%!  assocs_pair_assocs(?Assocs0, +Key-+Value, ?Assocs1) is nondet.
%
%  Assocs1 is Assocs0 with Key-Value added at the front. Can also
%  be used to decompose: if Assocs1 is known, extracts Key-Value
%  and the remaining Assocs0.
assocs_pair_assocs(T, K-V, [K-V|T]).
assocs_pair_assocs([H  |T], K-V, [H|T2]) :-
    assocs_pair_assocs(T, K-V, T2).

%!  pair_pair_assocs_assocs(+Old, +New, +Assocs0, -Assocs1) is semidet.
%
%  Assocs1 is Assocs0 with the pair matching Old replaced, in place, by
%  New. Old is Key0-Value0 with Key0 ground; the first pair with Key0 is
%  the one replaced, and its value must unify with Value0. Fails if
%  there is none.
pair_pair_assocs_assocs(K0-V0, New, [K-V|T0], A) :-
    (   K == K0
    ->  V = V0,
        A = [New|T0]
    ;   A = [K-V|T],
        pair_pair_assocs_assocs(K0-V0, New, T0, T)
    ).

%!  assocs_pair_removed(+Assocs, +Key-?Value, -Rest) is nondet.
%
%  Rest is Assocs with the first occurrence of Key-Value removed.
assocs_pair_removed([], _, []).
assocs_pair_removed([HK-HV|T], K-V, [HK-HV|R]) :-
    dif(HK, K),
    assocs_pair_removed(T, K-V, R).
assocs_pair_removed([K-V|R], K-V, R).
