open Monika_sugar

let ( let* ) = Result.bind

type apply_config = {
  workspace : string option;
  patch_file : string option;
  result_file : string option;
  patch_id : string option;
  dry_run : bool;
}

type inspect_config = {
  workspace : string option;
  artifact : string option;
}

type derive_config = {
  workspace : string option;
  artifact : string option;
  target : string option;
}

type resolve_config = {
  workspace : string option;
  artifact : string option;
  reference : string option;
  observed_at : string option;
}

type related_config = {
  workspace : string option;
  artifact : string option;
  direction : Workspace_graph.query_direction;
  direction_set : bool;
  predicate : string option;
  limit : int;
  limit_set : bool;
  json : bool;
}

let command_result ?summary ~command ~termination ~effect () =
  match
    Command_result.make ~command ~termination ~effect ?summary ()
  with
  | Ok result -> result
  | Error message -> invalid_arg ("invalid CLI CommandResult: " ^ message)

let invalid_input ~command message =
  command_result
    ~command
    ~termination:(Command_result.Usage_failure message)
    ~effect:Command_result.No_change
    ~summary:[ ("message", Command_result.Text message) ]
    ()

let print_result result =
  result |> Normal.Command_result.normalize |> Normal_json.command_result
  |> Yojson.Safe.pretty_to_channel stdout;
  print_newline ()

let process_exit_code result =
  match Command_result.exit_class result with
  | Command_result.Success -> 0
  | Command_result.Diagnostic_error -> 1
  | Command_result.Usage_error -> 2
  | Command_result.Internal_error_exit -> 3

let implementation_version () =
  match Build_info.V1.version () with
  | None -> "unknown"
  | Some version -> Build_info.V1.Version.to_string version

let print_version () =
  Printf.printf "monika %s\n" (implementation_version ())

let parse_apply_args args =
  let rec loop (config : apply_config) = function
    | [] -> Ok config
    | "--workspace" :: value :: rest -> (
        match config.workspace with
        | Some _ -> Error "--workspace must be provided at most once"
        | None -> loop { config with workspace = Some value } rest)
    | "--workspace" :: [] -> Error "--workspace requires a value"
    | "--patch" :: value :: rest -> (
        match config.patch_file with
        | Some _ -> Error "--patch must be provided at most once"
        | None -> loop { config with patch_file = Some value } rest)
    | "--patch" :: [] -> Error "--patch requires a value"
    | "--result" :: value :: rest -> (
        match config.result_file with
        | Some _ -> Error "--result must be provided at most once"
        | None -> loop { config with result_file = Some value } rest)
    | "--result" :: [] -> Error "--result requires a value"
    | "--patch-id" :: value :: rest -> (
        match config.patch_id with
        | Some _ -> Error "--patch-id must be provided at most once"
        | None -> loop { config with patch_id = Some value } rest)
    | "--patch-id" :: [] -> Error "--patch-id requires a value"
    | "--dry-run" :: rest ->
        if config.dry_run then Error "--dry-run must be provided at most once"
        else loop { config with dry_run = true } rest
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match
    loop
      {
        workspace = None;
        patch_file = None;
        result_file = None;
        patch_id = None;
        dry_run = false;
      }
      args
  with
  | Error _ as error -> error
  | Ok config -> (
      match
        ( config.workspace,
          config.patch_file,
          config.result_file,
          config.patch_id )
      with
      | None, _, _, _ -> Error "--workspace is required"
      | _, None, None, _ ->
          Error "exactly one of --patch or --result is required"
      | _, Some _, Some _, _ ->
          Error "--patch and --result are mutually exclusive"
      | _, Some _, None, Some _ ->
          Error "--patch-id may be used only with --result"
      | Some _, (Some _ | None), (Some _ | None), _ -> Ok config)

let read_patch file =
  try
    let json = Yojson.Safe.from_file file in
    Normal_decode.proposed_patch json
  with
  | Yojson.Json_error message -> Error ("invalid patch JSON: " ^ message)
  | Sys_error message -> Error message

let read_result_patch file requested_id =
  try
    let json = Yojson.Safe.from_file file in
    let* patch_values =
      match json with
      | `Assoc fields -> (
          let names = fields |> List.map fst |> List.sort String.compare in
          let rec has_duplicate = function
            | left :: (right :: _ as rest) ->
                String.equal left right || has_duplicate rest
            | _ -> false
          in
          if has_duplicate names then Error "result contains duplicate fields"
          else
            match List.assoc_opt "schemaVersion" fields with
            | Some (`String version)
              when String.equal version Normal.schema_version -> (
                match List.assoc_opt "patches" fields with
                | Some (`List values) -> Ok values
                | Some _ -> Error "result patches must be an array"
                | None -> Error "result has no patches field")
            | Some (`String _) -> Error "result uses an unsupported schemaVersion"
            | Some _ -> Error "result schemaVersion must be a string"
            | None -> Error "result has no schemaVersion field")
      | _ -> Error "result must be a JSON object"
    in
    let* patches =
      List.fold_left
        (fun result value ->
          let* decoded = result in
          let* patch = Normal_decode.proposed_patch value in
          Ok (patch :: decoded))
        (Ok []) patch_values
      |> Result.map List.rev
    in
    let ids =
      patches |> List.map Proposed_patch.id |> List.sort Patch_id.compare
    in
    let rec has_duplicate = function
      | left :: (right :: _ as rest) ->
          Patch_id.equal left right || has_duplicate rest
      | _ -> false
    in
    if has_duplicate ids then Error "result contains duplicate patch IDs"
    else
      match (requested_id, patches) with
      | None, [ patch ] -> Ok patch
      | None, [] -> Error "result contains no patches"
      | None, _ ->
          Error "--patch-id is required when result contains multiple patches"
      | Some encoded, _ ->
          let* id =
            Patch_id.make encoded
            |> Result.map_error (fun message -> "invalid --patch-id: " ^ message)
          in
          (match
             List.find_opt
               (fun patch -> Patch_id.equal id (Proposed_patch.id patch))
               patches
           with
          | Some patch -> Ok patch
          | None -> Error "result does not contain the requested patch ID")
  with
  | Yojson.Json_error message -> Error ("invalid result JSON: " ^ message)
  | Sys_error message -> Error message

let run_apply args =
  match parse_apply_args args with
  | Error message -> invalid_input ~command:"apply" message
  | Ok config -> (
      match (config.workspace, config.patch_file, config.result_file) with
      | Some workspace, Some patch_file, None -> (
          match read_patch patch_file with
          | Error message -> invalid_input ~command:"apply" message
          | Ok patch ->
              Filesystem_apply.apply ~workspace ~patch
                ~dry_run:config.dry_run)
      | Some workspace, None, Some result_file -> (
          match read_result_patch result_file config.patch_id with
          | Error message -> invalid_input ~command:"apply" message
          | Ok patch ->
              Filesystem_apply.apply ~workspace ~patch
                ~dry_run:config.dry_run)
      | _ ->
          invalid_input ~command:"apply"
            "unreachable invalid apply configuration")

let parse_scan_args args =
  let rec loop workspace = function
    | [] -> Ok workspace
    | "--workspace" :: value :: rest -> (
        match workspace with
        | Some _ -> Error "--workspace must be provided at most once"
        | None -> loop (Some value) rest)
    | "--workspace" :: [] -> Error "--workspace requires a value"
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match loop None args with
  | Error _ as error -> error
  | Ok None -> Error "--workspace is required"
  | Ok (Some workspace) -> Ok workspace

let run_scan args =
  match parse_scan_args args with
  | Error message -> invalid_input ~command:"scan" message
  | Ok workspace -> Workspace_scan.scan ~workspace

let run_check args =
  match parse_scan_args args with
  | Error message -> invalid_input ~command:"check" message
  | Ok workspace -> Workspace_check.check ~workspace

let parse_inspect_args args =
  let rec loop (config : inspect_config) = function
    | [] -> Ok config
    | "--workspace" :: value :: rest -> (
        match config.workspace with
        | Some _ -> Error "--workspace must be provided at most once"
        | None -> loop { config with workspace = Some value } rest)
    | "--workspace" :: [] -> Error "--workspace requires a value"
    | "--artifact" :: value :: rest -> (
        match config.artifact with
        | Some _ -> Error "--artifact must be provided at most once"
        | None -> loop { config with artifact = Some value } rest)
    | "--artifact" :: [] -> Error "--artifact requires a value"
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match loop { workspace = None; artifact = None } args with
  | Error _ as error -> error
  | Ok { workspace = None; _ } -> Error "--workspace is required"
  | Ok { artifact = None; _ } -> Error "--artifact is required"
  | Ok { workspace = Some workspace; artifact = Some encoded } ->
      Workspace_path.of_canonical_string encoded
      |> Result.map (fun artifact -> (workspace, artifact))
      |> Result.map_error (fun message -> "invalid --artifact: " ^ message)

let run_inspect args =
  match parse_inspect_args args with
  | Error message -> invalid_input ~command:"inspect" message
  | Ok (workspace, artifact) -> Workspace_inspect.inspect ~workspace ~artifact

let parse_derive_args args =
  let rec loop (config : derive_config) = function
    | [] -> Ok config
    | "--workspace" :: value :: rest -> (
        match config.workspace with
        | Some _ -> Error "--workspace must be provided at most once"
        | None -> loop { config with workspace = Some value } rest)
    | "--workspace" :: [] -> Error "--workspace requires a value"
    | "--artifact" :: value :: rest -> (
        match config.artifact with
        | Some _ -> Error "--artifact must be provided at most once"
        | None -> loop { config with artifact = Some value } rest)
    | "--artifact" :: [] -> Error "--artifact requires a value"
    | "--target" :: value :: rest -> (
        match config.target with
        | Some _ -> Error "--target must be provided at most once"
        | None -> loop { config with target = Some value } rest)
    | "--target" :: [] -> Error "--target requires a value"
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match loop { workspace = None; artifact = None; target = None } args with
  | Error _ as error -> error
  | Ok { workspace = None; _ } -> Error "--workspace is required"
  | Ok { artifact = None; _ } -> Error "--artifact is required"
  | Ok { target = None; _ } -> Error "--target is required"
  | Ok { target = Some target; _ } when not (String.equal target "sidecar") ->
      Error "--target must be sidecar"
  | Ok { workspace = Some workspace; artifact = Some encoded; target = Some _ } ->
      Workspace_path.of_canonical_string encoded
      |> Result.map (fun artifact -> (workspace, artifact))
      |> Result.map_error (fun message -> "invalid --artifact: " ^ message)

let run_derive args =
  match parse_derive_args args with
  | Error message -> invalid_input ~command:"derive" message
  | Ok (workspace, artifact) ->
      Workspace_derive.derive_sidecar ~workspace ~artifact

let parse_resolve_args args =
  let rec loop (config : resolve_config) = function
    | [] -> Ok config
    | "--workspace" :: value :: rest when config.workspace = None ->
        loop { config with workspace = Some value } rest
    | "--artifact" :: value :: rest when config.artifact = None ->
        loop { config with artifact = Some value } rest
    | "--reference" :: value :: rest when config.reference = None ->
        loop { config with reference = Some value } rest
    | "--observed-at" :: value :: rest when config.observed_at = None ->
        loop { config with observed_at = Some value } rest
    | ("--workspace" | "--artifact" | "--reference" | "--observed-at") :: [] ->
        Error "resolve option requires a value"
    | ("--workspace" | "--artifact" | "--reference" | "--observed-at") as option
      :: _ ->
        Error (option ^ " must be provided at most once")
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match
    loop
      { workspace = None; artifact = None; reference = None; observed_at = None }
      args
  with
  | Error _ as error -> error
  | Ok { workspace = None; _ } -> Error "--workspace is required"
  | Ok { artifact = None; _ } -> Error "--artifact is required"
  | Ok { reference = None; _ } -> Error "--reference is required"
  | Ok { observed_at = None; _ } -> Error "--observed-at is required"
  | Ok
      {
        workspace = Some workspace;
        artifact = Some encoded;
        reference = Some reference;
        observed_at = Some observed_at;
      } ->
      Result.bind
        (Workspace_path.of_canonical_string encoded
        |> Result.map_error (fun message -> "invalid --artifact: " ^ message))
        (fun artifact ->
          Workspace_resolve.canonical_observed_at observed_at
          |> Result.map (fun observed_at ->
                 (workspace, artifact, reference, observed_at)))

let run_resolve args =
  match parse_resolve_args args with
  | Error message -> invalid_input ~command:"resolve" message
  | Ok (workspace, artifact, reference, observed_at) ->
      Workspace_resolve.resolve_reference ~workspace ~artifact ~reference
        ~observed_at

let related_help =
  {|Usage:
  monika related --workspace <dir> --artifact <canonical-workspace-path>
    [--direction incoming|outgoing|both] [--predicate <predicate>]
    [--limit <positive-integer>] [--json]

Returns explicit incoming and outgoing workspace relations. The default output
is Agent-readable text. --json returns the compact related-result schema.
|}

let parse_related_args args =
  let initial =
    {
      workspace = None;
      artifact = None;
      direction = Workspace_graph.Both;
      direction_set = false;
      predicate = None;
      limit = 50;
      limit_set = false;
      json = false;
    }
  in
  let parse_direction = function
    | "incoming" -> Ok Workspace_graph.Incoming
    | "outgoing" -> Ok Workspace_graph.Outgoing
    | "both" -> Ok Workspace_graph.Both
    | _ -> Error "--direction must be incoming, outgoing, or both"
  in
  let parse_limit value =
    match int_of_string_opt value with
    | Some limit when limit > 0 -> Ok limit
    | Some _ | None -> Error "--limit must be a positive integer"
  in
  let rec loop config = function
    | [] -> Ok config
    | "--workspace" :: value :: rest -> (
        match config.workspace with
        | Some _ -> Error "--workspace must be provided at most once"
        | None -> loop { config with workspace = Some value } rest)
    | "--workspace" :: [] -> Error "--workspace requires a value"
    | "--artifact" :: value :: rest -> (
        match config.artifact with
        | Some _ -> Error "--artifact must be provided at most once"
        | None -> loop { config with artifact = Some value } rest)
    | "--artifact" :: [] -> Error "--artifact requires a value"
    | "--direction" :: value :: rest ->
        if config.direction_set then
          Error "--direction must be provided at most once"
        else
          Result.bind (parse_direction value) (fun direction ->
              loop { config with direction; direction_set = true } rest)
    | "--direction" :: [] -> Error "--direction requires a value"
    | "--predicate" :: value :: rest ->
        if Option.is_some config.predicate then
          Error "--predicate must be provided at most once"
        else if String.length value = 0 then
          Error "--predicate must not be empty"
        else loop { config with predicate = Some value } rest
    | "--predicate" :: [] -> Error "--predicate requires a value"
    | "--limit" :: value :: rest ->
        if config.limit_set then Error "--limit must be provided at most once"
        else
          Result.bind (parse_limit value) (fun limit ->
              loop { config with limit; limit_set = true } rest)
    | "--limit" :: [] -> Error "--limit requires a value"
    | "--json" :: rest ->
        if config.json then Error "--json must be provided at most once"
        else loop { config with json = true } rest
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  let* config = loop initial args in
  match (config.workspace, config.artifact) with
  | None, _ -> Error "--workspace is required"
  | _, None -> Error "--artifact is required"
  | Some workspace, Some encoded ->
      Workspace_path.of_canonical_string encoded
      |> Result.map (fun artifact -> (config, workspace, artifact))
      |> Result.map_error (fun message -> "invalid --artifact: " ^ message)

let run_related args =
  if args = [ "--help" ] then Ok (`Help related_help)
  else
    match parse_related_args args with
    | Error message -> Error (`Usage message)
    | Ok (config, workspace, artifact) ->
        Workspace_graph.query ~workspace ~artifact
          ~direction:config.direction ~predicate:config.predicate
          ~limit:config.limit
        |> Result.map (fun result -> `Result (config.json, result))
        |> Result.map_error (function
             | Workspace_graph.Usage message -> `Usage message
             | Workspace_graph.Internal message -> `Internal message)

let read_help =
  {|Usage:
  monika read --workspace <dir> --artifact <canonical-workspace-path>

Renders one supported artifact, its regions, references, annotations, and exact
content for direct Agent reading. Use monika inspect for normalized JSON.
|}

let print_read_diagnostics diagnostics =
  List.iter
    (fun diagnostic ->
      prerr_endline
        (Printf.sprintf "monika read: %s: %s"
           (Diagnostic.code diagnostic |> Diagnostic.code_string)
           (Diagnostic.message diagnostic)))
    diagnostics

let run_read args =
  if args = [ "--help" ] then Ok (`Help read_help)
  else
    match parse_inspect_args args with
    | Error message -> Error (`Usage message)
    | Ok (workspace, artifact) ->
        let observation =
          Workspace_inspect.inspect_observation ~workspace ~artifact
        in
        let result = observation.result in
        (match Command_result.termination result with
        | Command_result.Usage_failure message -> Error (`Usage message)
        | Command_result.Internal_failure _ ->
            Error (`Internal "workspace observation failed")
        | Command_result.Completed ->
            let diagnostics = Command_result.diagnostics result in
            if diagnostics <> [] then Error (`Diagnostics diagnostics)
            else
              match observation.content with
              | None -> Error (`Internal "interpreter returned no readable content")
              | Some _ ->
                  Ok (`Result (Read_text.to_string ~artifact observation)))

let parse_extension_test_args args =
  let rec loop descriptor = function
    | [] -> Ok descriptor
    | "--descriptor" :: value :: rest -> (
        match descriptor with
        | Some _ -> Error "--descriptor must be provided at most once"
        | None -> loop (Some value) rest)
    | "--descriptor" :: [] -> Error "--descriptor requires a value"
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match loop None args with
  | Error _ as error -> error
  | Ok None -> Error "--descriptor is required"
  | Ok (Some descriptor) -> Ok descriptor

let read_extension_descriptor file =
  try
    Yojson.Safe.from_file file |> Extension_descriptor.of_yojson
    |> Result.map_error (fun message -> "invalid extension descriptor: " ^ message)
  with
  | Yojson.Json_error _ -> Error "invalid extension descriptor JSON"
  | Sys_error _ -> Error "could not read extension descriptor"

let run_extension_test args =
  match parse_extension_test_args args with
  | Error message -> invalid_input ~command:"extension-test" message
  | Ok file -> (
      match read_extension_descriptor file with
      | Error message -> invalid_input ~command:"extension-test" message
      | Ok descriptor ->
          Command_result.make ~command:"extension-test"
            ~termination:Command_result.Completed ~effect:Command_result.No_change
            ~capabilities:[ Extension_descriptor.capability descriptor ]
            ~summary:
              [
                ("checkedCapabilities", Command_result.Count 1);
                ( "protocolVersion",
                  Command_result.Text
                    (Extension_descriptor.protocol_version descriptor) );
              ]
            ()
          |> Result.get_ok)

let main argv =
  match argv with
  | _program :: "scan" :: args -> run_scan args
  | _program :: "inspect" :: args -> run_inspect args
  | _program :: "check" :: args -> run_check args
  | _program :: "derive" :: args -> run_derive args
  | _program :: "resolve" :: args -> run_resolve args
  | _program :: "capabilities" :: [] -> Built_in_capabilities.command_result ()
  | _program :: "capabilities" :: _ ->
      invalid_input ~command:"capabilities" "capabilities accepts no arguments"
  | _program :: "extension" :: "test" :: args -> run_extension_test args
  | _program :: "extension" :: _ ->
      invalid_input ~command:"extension-test" "extension subcommand must be test"
  | _program :: "apply" :: args -> run_apply args
  | _program :: [] -> invalid_input ~command:"monika" "command is required"
  | _program :: command :: _ ->
      invalid_input ~command:"monika" ("unknown command: " ^ command)
  | [] -> invalid_input ~command:"monika" "command is required"

let () =
  let argv = Sys.argv |> Array.to_list in
  match argv with
  | [ _program; "--version" ] | [ _program; "-V" ] ->
      print_version ();
      exit 0
  | _program :: ("--version" | "-V") :: _ ->
      prerr_endline "monika: --version accepts no arguments";
      exit 2
  | _program :: "read" :: args -> (
      match run_read args with
      | Ok (`Help help) | Ok (`Result help) ->
          print_string help;
          exit 0
      | Error (`Usage message) ->
          prerr_endline ("monika read: " ^ message);
          exit 2
      | Error (`Diagnostics diagnostics) ->
          print_read_diagnostics diagnostics;
          exit 1
      | Error (`Internal message) ->
          prerr_endline ("monika read: " ^ message);
          exit 3)
  | _program :: "related" :: args -> (
      match run_related args with
      | Ok (`Help help) ->
          print_string help;
          exit 0
      | Ok (`Result (json, result)) ->
          print_string
            (if json then Related_json.to_string result
             else Related_text.to_string result);
          exit 0
      | Error (`Usage message) ->
          prerr_endline ("monika related: " ^ message);
          exit 2
      | Error (`Internal message) ->
          prerr_endline ("monika related: " ^ message);
          exit 3)
  | _ ->
      let result = main argv in
      print_result result;
      exit (process_exit_code result)
