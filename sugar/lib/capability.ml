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
  media_types : string list;
  path_globs : string list;
}

type schemas = {
  selector : string option;
  annotation : string option;
  options : string option;
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
  | Renderer -> "renderer"
  | Indexer -> "indexer"

let valid_string value = String.length value > 0 && Utf8.is_valid value

let no_duplicates values =
  let sorted = List.sort String.compare values in
  let rec loop = function
    | left :: (right :: _ as rest) ->
        not (String.equal left right) && loop rest
    | [] | [ _ ] -> true
  in
  loop sorted

let valid_optional = Option.fold ~none:true ~some:valid_string

let valid_path_globs values =
  List.for_all (fun value -> Result.is_ok (Path_glob.make value)) values

let make ~kind ~name ~version ?applies_to ?schemas () =
  if not (valid_string name) then Error "capability name must be non-empty UTF-8"
  else if not (valid_string version) then
    Error "capability version must be non-empty UTF-8"
  else if
    match applies_to with
    | None -> false
    | Some { media_types; path_globs } ->
        (media_types = [] && path_globs = [])
        || not (List.for_all valid_string (media_types @ path_globs))
        || not (no_duplicates media_types && no_duplicates path_globs)
  then Error "capability appliesTo must contain unique non-empty UTF-8 values"
  else if
    match applies_to with
    | None -> false
    | Some { path_globs; _ } -> not (valid_path_globs path_globs)
  then Error "capability pathGlobs contain invalid syntax"
  else if
    match schemas with
    | None -> false
    | Some { selector; annotation; options } ->
        (selector = None && annotation = None && options = None)
        || not
             (valid_optional selector && valid_optional annotation
            && valid_optional options)
  then Error "capability schemas must contain non-empty UTF-8 references"
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
