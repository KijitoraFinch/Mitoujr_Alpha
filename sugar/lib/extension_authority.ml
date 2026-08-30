type origin_class = Extension

type t =
  | Sandboxed of { launch_paths : string list }
  | Resource_observer of {
      launch_paths : string list;
      resource_read_paths : string list;
      network : bool;
    }

let default_sandboxed = Sandboxed { launch_paths = [] }

let ( let* ) = Result.bind

let contains_nul value = String.contains value '\000'

let is_path_separator = function '/' | '\\' -> true | _ -> false

let windows_drive_absolute path =
  String.length path >= 3
  &&
  match path.[0] with
  | 'A' .. 'Z' | 'a' .. 'z' -> path.[1] = ':' && is_path_separator path.[2]
  | _ -> false

let windows_unc_absolute path =
  let length = String.length path in
  if
    length < 5
    || not (is_path_separator path.[0] && is_path_separator path.[1])
  then false
  else
    let rec separator index =
      if index >= length then None
      else if is_path_separator path.[index] then Some index
      else separator (index + 1)
    in
    match separator 2 with
    | Some share_start when share_start > 2 && share_start + 1 < length ->
        not (is_path_separator path.[share_start + 1])
    | Some _ | None -> false

let is_absolute_path path =
  if Sys.win32 then
    windows_drive_absolute path || windows_unc_absolute path
  else not (Filename.is_relative path)

let normalize_paths field paths =
  let valid path =
    String.length path > 0
    && is_absolute_path path
    && Utf8.is_valid path
    && not (contains_nul path)
  in
  if not (List.for_all valid paths) then
    Error (field ^ " must contain absolute UTF-8 paths without NUL")
  else if List.length paths > 128 then Error (field ^ " exceeds the 128-path limit")
  else
    let normalized = List.sort_uniq String.compare paths in
    if List.length normalized <> List.length paths then
      Error (field ^ " must not contain duplicate paths")
    else Ok normalized

let sandboxed ~launch_paths =
  let* launch_paths = normalize_paths "authority.launchPaths" launch_paths in
  Ok (Sandboxed { launch_paths })

let resource_observer ~launch_paths ~resource_read_paths ~network =
  let* launch_paths = normalize_paths "authority.launchPaths" launch_paths in
  let* resource_read_paths =
    normalize_paths "authority.resourceReadPaths" resource_read_paths
  in
  Ok (Resource_observer { launch_paths; resource_read_paths; network })

let launch_paths = function
  | Sandboxed { launch_paths }
  | Resource_observer { launch_paths; _ } ->
      launch_paths

let resource_read_paths = function
  | Sandboxed _ -> []
  | Resource_observer { resource_read_paths; _ } -> resource_read_paths

let network = function
  | Sandboxed _ -> false
  | Resource_observer { network; _ } -> network

let origin_class = function
  | Sandboxed _ -> None
  | Resource_observer _ -> Some Extension

let validate_for_capability capability authority =
  match Capability.kind capability, authority with
  | Capability.Resource_observer, Resource_observer _ -> Ok ()
  | Capability.Resource_observer, Sandboxed _ ->
      Error "Resource Observer installation requires resource-observer authority"
  | ( Capability.Interpreter
    | Capability.Annotation_extractor
    | Capability.Reference_extractor
    | Capability.Auditor
    | Capability.Deriver ),
    Sandboxed _ ->
      Ok ()
  | _, Resource_observer _ ->
      Error "resource-observer authority is valid only for a Resource Observer"

let duplicate_name fields =
  let names = List.map fst fields |> List.sort String.compare in
  let rec loop = function
    | left :: (right :: _ as rest) ->
        String.equal left right || loop rest
    | [] | [ _ ] -> false
  in
  loop names

let fields path allowed = function
  | `Assoc values when duplicate_name values ->
      Error (path ^ ": object field names must be unique")
  | `Assoc values -> (
      match List.find_opt (fun (name, _) -> not (List.mem name allowed)) values with
      | Some (name, _) -> Error (path ^ ": unknown field " ^ name)
      | None -> Ok values)
  | _ -> Error (path ^ " must be an object")

let required path name values =
  match List.assoc_opt name values with
  | Some value -> Ok value
  | None -> Error (path ^ ": missing field " ^ name)

let string path = function
  | `String value when Utf8.is_valid value -> Ok value
  | _ -> Error (path ^ " must be a UTF-8 string")

let path_list path = function
  | `List values ->
      values
      |> List.mapi (fun index value ->
             string (Printf.sprintf "%s[%d]" path index) value)
      |> fun items ->
      List.fold_right
        (fun item result ->
          let* item = item in
          let* result = result in
          Ok (item :: result))
        items (Ok [])
  | _ -> Error (path ^ " must be an array")

let of_yojson json =
  let path = "authority" in
  let* values =
    fields path
      [
        "kind";
        "originClass";
        "launchPaths";
        "resourceReadPaths";
        "network";
      ]
      json
  in
  let* kind_json = required path "kind" values in
  let* kind = string (path ^ ".kind") kind_json in
  match kind with
  | "sandboxed" ->
      let* launch_paths_json = required path "launchPaths" values in
      let* launch_paths = path_list (path ^ ".launchPaths") launch_paths_json in
      if List.length values <> 2 then
        Error "authority: sandboxed authority permits only kind and launchPaths"
      else sandboxed ~launch_paths
  | "resource-observer" ->
      let* origin_class_json = required path "originClass" values in
      let* origin_class = string (path ^ ".originClass") origin_class_json in
      if not (String.equal origin_class "extension") then
        Error "authority.originClass must be extension"
      else
        let* launch_paths_json = required path "launchPaths" values in
        let* launch_paths = path_list (path ^ ".launchPaths") launch_paths_json in
        let* resource_read_paths_json =
          required path "resourceReadPaths" values
        in
        let* resource_read_paths =
          path_list (path ^ ".resourceReadPaths") resource_read_paths_json
        in
        let* network =
          match List.assoc_opt "network" values with
          | Some (`Bool value) -> Ok value
          | Some _ -> Error "authority.network must be a boolean"
          | None -> Error "authority: missing field network"
        in
        if List.length values <> 5 then
          Error
            "authority: resource-observer authority requires exactly kind, originClass, launchPaths, resourceReadPaths, and network"
        else resource_observer ~launch_paths ~resource_read_paths ~network
  | _ -> Error "authority.kind is unsupported"

let string_list values = `List (List.map (fun value -> `String value) values)

let to_yojson = function
  | Sandboxed { launch_paths } ->
      `Assoc
        [
          ("kind", `String "sandboxed");
          ("launchPaths", string_list launch_paths);
        ]
  | Resource_observer { launch_paths; resource_read_paths; network } ->
      `Assoc
        [
          ("kind", `String "resource-observer");
          ("originClass", `String "extension");
          ("launchPaths", string_list launch_paths);
          ("resourceReadPaths", string_list resource_read_paths);
          ("network", `Bool network);
        ]

let compare left right =
  Stdlib.compare (to_yojson left) (to_yojson right)
