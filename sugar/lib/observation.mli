type origin = Origin.t
type structured_value = {
  schema : string;
  value : Normalized_value.t;
}

type representation =
  | Bytes of string
  | Structured of structured_value

type t

val workspace : Workspace_path.t -> origin
val git : repo:string -> ?rev:string -> path:string -> unit -> (origin, string) result
val web : string -> (origin, string) result
val generated : string -> (origin, string) result
val external_ : string -> (origin, string) result
val extension :
  observer:Resource_observer.t ->
  locator:Yojson.Safe.t ->
  unit ->
  (origin, string) result

val make :
  id:Observation_id.t ->
  origin:Origin.t ->
  identity:Observation_identity.t ->
  representation:representation ->
  unit ->
  (t, string) result

val of_bytes :
  id:Observation_id.t ->
  origin:Origin.t ->
  observation_type:Observation_type.t ->
  bytes:string ->
  t

val of_structured :
  id:Observation_id.t ->
  origin:Origin.t ->
  identity:Observation_identity.t ->
  schema:string ->
  value:Yojson.Safe.t ->
  unit ->
  (t, string) result

val id : t -> Observation_id.t
val origin : t -> Origin.t
val observation_type : t -> Observation_type.t
val identity : t -> Observation_identity.t
val representation : t -> representation
val bytes : t -> string option
val content_identity : t -> Content_identity.t option
val same : t -> t -> bool
val compare_origin : Origin.t -> Origin.t -> int
