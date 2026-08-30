type kind =
  | Resource_observer
  | Interpreter
  | Annotation_extractor
  | Reference_extractor
  | Deriver
  | Auditor

type applies_to = {
  observation_types : Observation_type.t list;
  path_globs : string list;
}

type schemas = {
  selector_schemas : string list;
  result_schemas : string list;
}

type t = {
  kind : kind;
  name : string;
  version : string;
  applies_to : applies_to option;
  schemas : schemas option;
}

let kind_string = function
  | Resource_observer -> "resource-observer"
  | Interpreter -> "interpreter"
  | Annotation_extractor -> "annotation-extractor"
  | Reference_extractor -> "reference-extractor"
  | Deriver -> "deriver"
  | Auditor -> "auditor"

let valid_string value = String.length value > 0 && Utf8.is_valid value

let no_duplicates values =
  let sorted = List.sort String.compare values in
  let rec loop = function
    | left :: (right :: _ as rest) ->
        not (String.equal left right) && loop rest
    | [] | [ _ ] -> true
  in
  loop sorted

let valid_path_globs values =
  List.for_all (fun value -> Result.is_ok (Path_glob.make value)) values

let make ~kind ~name ~version ?applies_to ?schemas () =
  if not (valid_string name) then Error "capability name must be non-empty UTF-8"
  else if not (valid_string version) then
    Error "capability version must be non-empty UTF-8"
  else if
    match applies_to with
    | None -> false
    | Some { observation_types; path_globs } ->
        not (List.for_all valid_string path_globs)
        || not (no_duplicates path_globs)
        ||
        let normalized =
          List.map
            (fun value ->
              Observation_type.name value ^ "\000"
              ^ Observation_type.version value)
            observation_types
        in
        not (no_duplicates normalized)
  then
    Error
      "capability applicability must contain unique non-empty UTF-8 path globs"
  else if
    match applies_to with
    | None -> false
    | Some { path_globs; _ } -> not (valid_path_globs path_globs)
  then Error "capability pathGlobs contain invalid syntax"
  else if
    match schemas with
    | None -> false
    | Some { selector_schemas; result_schemas } ->
        result_schemas = []
        || not
             (List.for_all valid_string
                (selector_schemas @ result_schemas))
        || not
             (no_duplicates selector_schemas && no_duplicates result_schemas)
  then
    Error
      "capability result schemas must be non-empty and all schema identities must be unique non-empty UTF-8"
  else Ok { kind; name; version; applies_to; schemas }

let kind value = value.kind
let name value = value.name
let version value = value.version
let applies_to value = value.applies_to
let schemas value = value.schemas

let compare left right =
  match String.compare (kind_string left.kind) (kind_string right.kind) with
  | 0 -> (
      match String.compare left.name right.name with
      | 0 -> String.compare left.version right.version
      | other -> other)
  | other -> other
