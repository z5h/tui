:- module(watch,
          [ watch/2                    % Var, ?Domain
          ]).

:- meta_predicate(watch(?, 0)).
:- det(watch/2).
watch(X, Goal) :-
    var(X), !,
    put_attr(X, watch, var_goal(X, Goal)).


watch(_, Goal) :-
    call(Goal).

debug_name_attvar(N, A) :-
    (  attvar(A)
    -> writeln(N:attvar:true)
    ;  A = call(_)
    -> writeln(N:callable)
    ;  writeln(N:unknown)
    ).

attr_unify_hook(VG, _) :-
    (  var_goal(V, G) = VG
    -> del_attr(V, watch),
       call(G), !
    ;  true
    ).

%       Translate attributes from this module to residual goals
attribute_goals(X) -->
        { get_attr(X, watch, Goal) },
        [watch(X, Goal)].

