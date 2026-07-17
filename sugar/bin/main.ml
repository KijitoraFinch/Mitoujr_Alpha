open Monika_sugar

type apply_config = {
  workspace : string option;
  patch_file : string option;
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
    | "--dry-run" :: rest ->
        if config.dry_run then Error "--dry-run must be provided at most once"
        else loop { config with dry_run = true } rest
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match loop { workspace = None; patch_file = None; dry_run = false } args with
  | Error _ as error -> error
  | Ok config -> (
      match (config.workspace, config.patch_file) with
      | None, _ -> Error "--workspace is required"
      | _, None -> Error "--patch is required"
      | Some _, Some _ -> Ok config)

let read_patch file =
  try
    let json = Yojson.Safe.from_file file in
    Normal_decode.proposed_patch json
  with
  | Yojson.Json_error message -> Error ("invalid patch JSON: " ^ message)
  | Sys_error message -> Error message

let run_apply args =
  match parse_apply_args args with
  | Error message -> invalid_input ~command:"apply" message
  | Ok config -> (
      match (config.workspace, config.patch_file) with
      | Some workspace, Some patch_file -> (
          match read_patch patch_file with
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
  let result = Sys.argv |> Array.to_list |> main in
  print_result result;
  exit (process_exit_code result)
