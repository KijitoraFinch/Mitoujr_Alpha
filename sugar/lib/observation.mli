type t

val make : origin:Origin.t -> identity:Observation_identity.t -> t
val origin : t -> Origin.t
val observation_type : t -> Observation_type.t
val identity : t -> Observation_identity.t
val same : t -> t -> bool
