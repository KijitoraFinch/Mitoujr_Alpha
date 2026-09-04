type operation =
  | Session
  | Interpret_observation
  | Extract_annotations
  | Extract_references
  | Observe_resource
  | Audit
  | Derive
  | Resolve_region
  | Classify_region_extents

type t = {
  operation : operation;
  code : string;
  message : string;
  data : Yojson.Safe.t option;
}

let maximum_json_depth = 128

let duplicate_name fields =
  let names = List.map fst fields |> List.sort String.compare in
  let rec loop = function
    | left :: (right :: _ as rest) ->
        String.equal left right || loop rest
    | [] | [ _ ] -> false
  in
  loop names

let rec normalize_json depth path json =
  if depth > maximum_json_depth then
    Error (path ^ ": JSON nesting exceeds the protocol limit")
  else
    match json with
    | `Null -> Ok `Null
    | `Bool value -> Ok (`Bool value)
    | `String value when Utf8.is_valid value -> Ok (`String value)
    | `String _ -> Error (path ^ ": string must be valid UTF-8")
    | `Int value when Protocol_integer.is_safe value -> Ok (`Int value)
    | `Int _ -> Error (path ^ ": integer exceeds the protocol safe range")
    | `Intlit encoded -> (
        match int_of_string_opt encoded with
        | Some value when Protocol_integer.is_safe value -> Ok (`Int value)
        | _ -> Error (path ^ ": integer exceeds the protocol safe range"))
    | `List values ->
        values
        |> List.mapi (fun index value ->
               normalize_json (depth + 1)
                 (Printf.sprintf "%s[%d]" path index)
                 value)
        |> List.fold_left
             (fun result value ->
               Result.bind result (fun values ->
                   Result.map (fun value -> value :: values) value))
             (Ok [])
        |> Result.map List.rev |> Result.map (fun values -> `List values)
    | `Assoc fields ->
        if List.exists (fun (name, _) -> not (Utf8.is_valid name)) fields then
          Error (path ^ ": object field name must be valid UTF-8")
        else if duplicate_name fields then
          Error (path ^ ": object field names must be unique")
        else
          fields
          |> List.sort (fun (left, _) (right, _) -> String.compare left right)
          |> List.fold_left
               (fun result (name, value) ->
                 Result.bind result (fun fields ->
                     Result.map
                       (fun value -> (name, value) :: fields)
                       (normalize_json (depth + 1) (path ^ "." ^ name) value)))
               (Ok [])
          |> Result.map List.rev |> Result.map (fun fields -> `Assoc fields)
    | `Float _ -> Error (path ^ ": floating-point values are not supported")
    | `Tuple _ | `Variant _ -> Error (path ^ ": value must be protocol JSON")

let valid value = String.length value > 0 && Utf8.is_valid value

let make ~operation ~code ~message ?data () =
  if not (valid code) then
    Error "extension failure code must be non-empty UTF-8"
  else if not (valid message) then
    Error "extension failure message must be non-empty UTF-8"
  else
    match data with
    | None -> Ok { operation; code; message; data = None }
    | Some data ->
        Result.map
          (fun data -> { operation; code; message; data = Some data })
          (normalize_json 0 "$extensionFailure.data" data)

let operation value = value.operation

let operation_string = function
  | Session -> "session"
  | Interpret_observation -> "interpret-observation"
  | Extract_annotations -> "extract-annotations"
  | Extract_references -> "extract-references"
  | Observe_resource -> "observe-resource"
  | Audit -> "audit"
  | Derive -> "derive"
  | Resolve_region -> "resolve-region"
  | Classify_region_extents -> "classify-region-extents"

let code value = value.code
let message value = value.message
let data value = value.data

let compare left right =
  match String.compare (operation_string left.operation) (operation_string right.operation) with
  | 0 -> (
      match String.compare left.code right.code with
      | 0 -> (
          match String.compare left.message right.message with
          | 0 -> Option.compare Stdlib.compare left.data right.data
          | other -> other)
      | other -> other)
  | other -> other

let equal left right = compare left right = 0
