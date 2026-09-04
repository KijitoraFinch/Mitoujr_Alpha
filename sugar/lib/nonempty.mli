type 'a t

val make : 'a -> 'a list -> 'a t
val singleton : 'a -> 'a t
val of_list : 'a list -> 'a t option
val head : 'a t -> 'a
val tail : 'a t -> 'a list
val to_list : 'a t -> 'a list
val length : 'a t -> int
val map : ('a -> 'b) -> 'a t -> 'b t
val exists : ('a -> bool) -> 'a t -> bool
val iter : ('a -> unit) -> 'a t -> unit
