type kind =
  | Resource_observer
  | Interpreter
  | Annotation_extractor
  | Reference_extractor
  | Deriver
  | Auditor
  | Renderer
  | Indexer

type applies_to = {
  observation_types : Observation_type.t list;
  (** Complete workspace-relative path globs. [*] stays within one segment and
      [**] must occupy a complete segment. Matching is case-sensitive. *)
  path_globs : string list;
}

type schemas = {
  selector_schemas : string list;
  result_schemas : string list;
}

type t

val make :
  kind:kind ->
  name:string ->
  version:string ->
  ?applies_to:applies_to ->
  ?schemas:schemas ->
  unit ->
  (t, string) result

val kind : t -> kind
val name : t -> string
val version : t -> string
val applies_to : t -> applies_to option
val schemas : t -> schemas option
val kind_string : kind -> string
val compare : t -> t -> int
