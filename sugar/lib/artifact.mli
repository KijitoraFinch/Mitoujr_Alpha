type origin = Origin.t

type t

val workspace : Workspace_path.t -> origin
val git : repo:string -> ?rev:string -> path:string -> unit -> (origin, string) result
val web : string -> (origin, string) result
val generated : string -> (origin, string) result
val external_ : string -> (origin, string) result
val extension :
  provider:string -> locator:string -> unit -> (origin, string) result

val make :
  id:Artifact_id.t ->
  origin:origin ->
  ?media_type:string ->
  content_identity:Content_identity.t ->
  unit ->
  (t, string) result

val id : t -> Artifact_id.t
val origin : t -> origin
val media_type : t -> string option
val content_identity : t -> Content_identity.t
val observation : t -> Observation.t
val observation_identity : t -> Observation_identity.t
val compare_origin : origin -> origin -> int
