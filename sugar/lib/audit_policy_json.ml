let encode value =
  let sidecar_only =
    match Audit_policy.sidecar_only value with
    | Audit_policy.Allow -> "allow"
    | Audit_policy.Report -> "report"
  in
  let severity_overrides =
    Audit_policy.severity_overrides value
    |> List.map (fun (code, severity) ->
           `Assoc
             [
               ("code", `String (Diagnostic.code_string code));
               ("severity", `String (Diagnostic.severity_string severity));
             ])
  in
  `Assoc
    [
      ("sidecarOnly", `String sidecar_only);
      ("severityOverrides", `List severity_overrides);
    ]

let ( let* ) = Result.bind

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
          match
            List.find_opt (fun name -> not (List.mem_assoc name fields)) required
          with
          | Some name -> Error (path ^ ": missing field " ^ name)
          | None -> Ok fields))
  | _ -> Error (path ^ " must be an object")

let string path = function
  | `String value when Utf8.is_valid value -> Ok value
  | _ -> Error (path ^ " must be a UTF-8 string")

let sidecar_only = function
  | `String "allow" -> Ok Audit_policy.Allow
  | `String "report" -> Ok Audit_policy.Report
  | _ -> Error "policy.sidecarOnly must be allow or report"

let severity_override index json =
  let path = Printf.sprintf "policy.severityOverrides[%d]" index in
  let* fields = object_fields path ~required:[ "code"; "severity" ] json in
  let* code = string (path ^ ".code") (List.assoc "code" fields) in
  let* code =
    Diagnostic.code_of_string code
    |> Result.map_error (fun message -> path ^ ".code: " ^ message)
  in
  let* severity =
    string (path ^ ".severity") (List.assoc "severity" fields)
  in
  let* severity =
    Diagnostic.severity_of_string severity
    |> Result.map_error (fun message -> path ^ ".severity: " ^ message)
  in
  Ok (code, severity)

let severity_overrides = function
  | `List values ->
      let items = List.mapi severity_override values in
      List.fold_right
        (fun item result ->
          let* item = item in
          let* result = result in
          Ok (item :: result))
        items (Ok [])
  | _ -> Error "policy.severityOverrides must be an array"

let of_yojson json =
  let* fields =
    object_fields "policy" ~required:[ "sidecarOnly"; "severityOverrides" ] json
  in
  let* sidecar_only = sidecar_only (List.assoc "sidecarOnly" fields) in
  let* severity_overrides =
    severity_overrides (List.assoc "severityOverrides" fields)
  in
  Audit_policy.make ~sidecar_only ~severity_overrides
  |> Result.map_error (fun message -> "policy: " ^ message)

let maximum_policy_bytes = 1024 * 1024

let load path =
  try
    let input = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr input) (fun () ->
        let length = in_channel_length input in
        if length > maximum_policy_bytes then
          Error "audit policy exceeds the 1 MiB size limit"
        else
          let content = really_input_string input length in
          if not (Utf8.is_valid content) then
            Error "audit policy must be UTF-8 JSON"
          else
            try Yojson.Safe.from_string content |> of_yojson
            with Yojson.Json_error message ->
              Error ("audit policy is not valid JSON: " ^ message))
  with Sys_error message -> Error message
