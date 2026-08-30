type origin = Origin.t
type t

val workspace : Workspace_path.t -> origin
val git : repo:string -> ?rev:string -> path:string -> unit -> (origin, string) result
val web : string -> (origin, string) result
val generated : string -> (origin, string) result
val external_ : string -> (origin, string) result
val extension :
  observer:string -> locator:string -> unit -> (origin, string) result

val make :
  id:Observation_id.t ->
  origin:Origin.t ->
  identity:Observation_identity.t ->
  ?content_identity:Content_identity.t ->
  unit ->
  t

val of_content :
  id:Observation_id.t ->
  origin:Origin.t ->
  observation_type:Observation_type.t ->
  content_identity:Content_identity.t ->
  t

val id : t -> Observation_id.t
val origin : t -> Origin.t
val observation_type : t -> Observation_type.t
val identity : t -> Observation_identity.t
val content_identity : t -> Content_identity.t option
val same : t -> t -> bool
val compare_origin : Origin.t -> Origin.t -> int
