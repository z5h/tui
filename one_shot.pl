:- module(one_shot,
          [one_shot_message/2
          ]
).


one_shot_message(Var, ReadStream) :-
    pipe(ReadStream, WriteStream),
    freeze(Var,
           (   write_canonical(WriteStream, Var),
               write(WriteStream, '.\n'),
               flush_output(WriteStream),
               close(WriteStream)
           )).
