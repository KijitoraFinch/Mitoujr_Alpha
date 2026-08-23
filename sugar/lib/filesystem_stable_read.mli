type 'value observation = Stable of 'value | Changed
type attempts

val make_attempts : int -> (attempts, string) result
val twice : attempts

(** Repeats [attempt] up to [attempts] times while it reports [Changed].
    [on_unstable] is returned only after every permitted observation changed.
    The attempt bound is explicit so concurrent mutation cannot cause an
    unbounded scan. *)
val retry :
  attempts:attempts ->
  on_unstable:'error ->
  (unit -> ('value observation, 'error) result) ->
  ('value, 'error) result
