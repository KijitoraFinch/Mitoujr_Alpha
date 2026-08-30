type t = Installed_extension.t list

let ( let* ) = Result.bind
let empty = []

let same_capability left right =
  Capability.compare (Installed_extension.capability left)
    (Installed_extension.capability right)
  = 0

let make extensions =
  let extensions = List.sort Installed_extension.compare extensions in
  let rec duplicates = function
    | left :: (right :: _ as rest) ->
        if same_capability left right then
          let capability = Installed_extension.capability left in
          Error
            (Printf.sprintf "duplicate installed capability: %s/%s/%s"
               (Capability.kind_string (Capability.kind capability))
               (Capability.name capability) (Capability.version capability))
        else duplicates rest
    | [] | [ _ ] -> Ok extensions
  in
  duplicates extensions

let extensions value = value

let find_interpreter value interpreter =
  List.find_opt
    (fun extension ->
      let capability = Installed_extension.capability extension in
      Capability.kind capability = Capability.Interpreter
      && String.equal (Capability.name capability) (Interpreter.name interpreter)
      && String.equal (Capability.version capability)
           (Interpreter.version interpreter))
    value

let applicable value ~kind ~observation =
  List.fold_left
    (fun result extension ->
      let* accepted = result in
      let capability = Installed_extension.capability extension in
      if Capability.kind capability <> kind then Ok accepted
      else
        let* applies =
          Extension_applicability.accepts capability ~observation
        in
        Ok (if applies then extension :: accepted else accepted))
    (Ok []) value
  |> Result.map List.rev

let duplicate_name fields =
  let names = List.map fst fields |> List.sort String.compare in
  let rec loop = function
    | left :: (right :: _ as rest) -> String.equal left right || loop rest
    | [] | [ _ ] -> false
  in
  loop names

let object_fields path ~required = function
  | `Assoc fields when duplicate_name fields ->
      Error (path ^ ": object field names must be unique")
  | `Assoc fields -> (
      match
        List.find_opt (fun (name, _) -> not (List.mem name required)) fields
      with
      | Some (name, _) -> Error (path ^ ": unknown field " ^ name)
      | None -> (
          match List.find_opt (fun name -> not (List.mem_assoc name fields)) required with
          | Some name -> Error (path ^ ": missing field " ^ name)
          | None -> Ok fields))
  | _ -> Error (path ^ " must be an object")

let string path = function
  | `String value when Utf8.is_valid value -> Ok value
  | _ -> Error (path ^ " must be a UTF-8 string")

let string_list path = function
  | `List values ->
      List.fold_right
        (fun item result ->
          let* item = item in
          let* result = result in
          Ok (item :: result))
        (List.mapi
           (fun index value ->
             string (Printf.sprintf "%s[%d]" path index) value)
           values)
        (Ok [])
  | _ -> Error (path ^ " must be an array")

let decode_extension index json =
  let path = Printf.sprintf "registry.extensions[%d]" index in
  let* fields =
    object_fields path ~required:[ "manifest"; "executable"; "arguments" ] json
  in
  let* manifest =
    Extension_manifest.of_yojson (List.assoc "manifest" fields)
    |> Result.map_error (fun message -> path ^ ".manifest: " ^ message)
  in
  let* executable = string (path ^ ".executable") (List.assoc "executable" fields) in
  let* arguments = string_list (path ^ ".arguments") (List.assoc "arguments" fields) in
  Installed_extension.make ~manifest ~executable ~arguments
  |> Result.map_error (fun message -> path ^ ": " ^ message)

let of_yojson json =
  let* fields =
    object_fields "registry" ~required:[ "schemaVersion"; "extensions" ] json
  in
  let* schema_version =
    string "registry.schemaVersion" (List.assoc "schemaVersion" fields)
  in
  if not (String.equal schema_version "1") then
    Error ("unsupported extension registry schema version: " ^ schema_version)
  else
    match List.assoc "extensions" fields with
    | `List values ->
        List.fold_right
          (fun item result ->
            let* item = item in
            let* result = result in
            Ok (item :: result))
          (List.mapi decode_extension values) (Ok [])
        |> fun result -> Result.bind result make
    | _ -> Error "registry.extensions must be an array"

let maximum_registry_bytes = 16 * 1024 * 1024

let load path =
  try
    let input = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr input) (fun () ->
        let length = in_channel_length input in
        if length > maximum_registry_bytes then
          Error "extension registry exceeds the 16 MiB size limit"
        else
          let content = really_input_string input length in
          if not (Utf8.is_valid content) then
            Error "extension registry must be UTF-8 JSON"
          else
            try Yojson.Safe.from_string content |> of_yojson
            with Yojson.Json_error message ->
              Error ("extension registry is not valid JSON: " ^ message))
  with Sys_error message -> Error message
