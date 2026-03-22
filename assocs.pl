:- module(assocs, [ empty_assocs/1,
                    empty_assocs//0,
                    assocs_pair/2,
                    assocs_pairs/2,
                    pair_pair_assocs_assocs/4,
                    assocs_pair_assocs/3,
                    op(920, fy, '~>'),
                    op(920, fy, '<~'),
                    '~>'//1,
                    '<~'//1
                  ]).


state(S, S, S).
state(S0, S, S0, S).

empty_assocs([]).

empty_assocs -->
    state([]).


assocs_pair([ K-V  |_ ], K-V).
assocs_pair([ _  |T ], K-V) :-
    assocs_pair(T, K-V).


assocs_pairs(_, []).
assocs_pairs(A, [P|T]) :-
    assocs_pair(A, P),
    assocs_pairs(A, T).

assocs_pair_assocs(T, K-V, [K-V|T]).
assocs_pair_assocs([H  |T], K-V, [H|T2]) :-
    assocs_pair_assocs(T, K-V, T2).


pair_pair_assocs_assocs(K0-V0, K1-V1, A0, A1) :-
    assocs_pair_assocs(A, K0-V0, A0),
    assocs_pair_assocs(A, K1-V1, A1).


<~(K-V) -->
    state(S),
    { assocs_pair(S, K-V) }.


assocs_pair_removed([], _, []).
assocs_pair_removed([HK-HV|T], K-V, [HK-HV|R]) :-
    dif(HK, K),
    assocs_pair_removed(T, K-V, R).
assocs_pair_removed([K-V|R], K-V, R).

~>(K-V) -->
    state(S0, S1),
    {   exclude('='(K-_), S0, R), S1 = [K-V|R], !
    }.
