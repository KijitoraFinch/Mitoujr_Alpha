open Monika_sugar

let ( let* ) = Result.bind

type apply_config = {
  workspace : string option;
  patch_file : string option;
  result_file : string option;
  patch_id : string option;
  dry_run : bool;
}

type extension_runtime_config = {
  manifest : string option;
  executable : string option;
  arguments_reversed : string list;
  launch_paths_reversed : string list;
}

type inspect_config = {
  workspace : string option;
  observation : string option;
  extension_registry : string option;
  extension : extension_runtime_config;
}

type derive_config = {
  workspace : string option;
  observation : string option;
  annotation : string option;
  reference_definition : string option;
  target : string option;
  extension_registry : string option;
  deriver : string option;
}

type resolve_config = {
  workspace : string option;
  observation : string option;
  reference : string option;
  address_file : string option;
  observed_at : string option;
  previous_snapshot : string option;
  extension_registry : string option;
  extension : extension_runtime_config;
}

type resolve_target =
  | Declared_reference of {
      observation : Workspace_path.t;
      reference : string;
    }
  | Direct_address of Region_address.t

type related_config = {
  workspace : string option;
  observation : string option;
  region : string option;
  region_scope : Workspace_graph.region_scope;
  region_scope_set : bool;
  direction : Workspace_graph.query_direction;
  direction_set : bool;
  predicate : string option;
  limit : int;
  limit_set : bool;
  json : bool;
  extension_registry : string option;
  extension : extension_runtime_config;
}

type extension_test_config = {
  manifest : string option;
  executable : string option;
  arguments_reversed : string list;
  launch_paths_reversed : string list;
  resource_read_paths_reversed : string list;
  allow_network : bool;
}

let sandboxed_authority reversed =
  Extension_authority.sandboxed ~launch_paths:(List.rev reversed)

let command_result ?summary ?(diagnostics = []) ?(capabilities = []) ~command
    ~termination ~effect () =
  match
    Command_result.make ~command ~termination ~effect ~diagnostics ~capabilities
      ?summary ()
  with
  | Ok result -> result
  | Error _ ->
      Command_result.internal_error ~command ~error_code:"internal-invariant"
        ~operation:"construct-command-result"

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
  if not (String.equal Build_identity.value "unknown") then Build_identity.value
  else
    match Build_info.V1.version () with
    | None -> "unknown"
    | Some version -> Build_info.V1.Version.to_string version

let print_version () =
  Printf.printf "monika %s\n" (implementation_version ())

let read_extension_manifest file =
  try
    Yojson.Safe.from_file file |> Extension_manifest.of_yojson
    |> Result.map_error (fun message -> "invalid extension manifest: " ^ message)
  with
  | Yojson.Json_error _ -> Error "invalid extension manifest JSON"
  | Sys_error _ -> Error "could not read extension manifest"

let read_extension_registry file =
  let* registry =
    Registry_snapshot.load file
    |> Result.map_error (fun message -> "invalid extension registry: " ^ message)
  in
  let* _capabilities =
    Built_in_capabilities.with_registry registry
  in
  Ok registry

let read_audit_policy file =
  Audit_policy_json.load file
  |> Result.map_error (fun message -> "invalid audit policy: " ^ message)

let read_resolution_snapshot file =
  Resolution_snapshot_json.load file
  |> Result.map_error (fun message -> "invalid resolution snapshot: " ^ message)

let read_region_address file =
  Region_address_json.load file
  |> Result.map_error (fun message -> "invalid RegionAddress: " ^ message)

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

let parse_check_args args =
  let rec loop workspace extension_registry policy = function
    | [] -> Ok (workspace, extension_registry, policy)
    | "--workspace" :: value :: rest -> (
        match workspace with
        | Some _ -> Error "--workspace must be provided at most once"
        | None -> loop (Some value) extension_registry policy rest)
    | "--workspace" :: [] -> Error "--workspace requires a value"
    | "--extension-registry" :: value :: rest -> (
        match extension_registry with
        | Some _ -> Error "--extension-registry must be provided at most once"
        | None -> loop workspace (Some value) policy rest)
    | "--extension-registry" :: [] ->
        Error "--extension-registry requires a value"
    | "--policy" :: value :: rest -> (
        match policy with
        | Some _ -> Error "--policy must be provided at most once"
        | None -> loop workspace extension_registry (Some value) rest)
    | "--policy" :: [] -> Error "--policy requires a value"
    | flag :: _ when String.starts_with ~prefix:"--" flag ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match loop None None None args with
  | Error _ as error -> error
  | Ok (None, _, _) -> Error "--workspace is required"
  | Ok (Some workspace, extension_registry, policy) ->
      Ok (workspace, extension_registry, policy)

let run_check args =
  match parse_check_args args with
  | Error message -> invalid_input ~command:"check" message
  | Ok (workspace, registry_file, policy_file) -> (
      let registry =
        match registry_file with
        | None -> Ok Registry_snapshot.empty
        | Some file -> read_extension_registry file
      in
      let policy =
        match policy_file with
        | None -> Ok Audit_policy.default
        | Some file -> read_audit_policy file
      in
      match registry, policy with
      | Error message, _ | _, Error message ->
          invalid_input ~command:"check" message
      | Ok registry, Ok policy ->
          Workspace_check.check_with_registry ~workspace ~registry ~policy)

let parse_inspect_args args =
  let rec loop (config : inspect_config) = function
    | [] -> Ok config
    | "--workspace" :: value :: rest -> (
        match config.workspace with
        | Some _ -> Error "--workspace must be provided at most once"
        | None -> loop { config with workspace = Some value } rest)
    | "--workspace" :: [] -> Error "--workspace requires a value"
    | "--observation" :: value :: rest -> (
        match config.observation with
        | Some _ -> Error "--observation must be provided at most once"
        | None -> loop { config with observation = Some value } rest)
    | "--observation" :: [] -> Error "--observation requires a value"
    | "--extension-registry" :: value :: rest -> (
        match config.extension_registry with
        | Some _ -> Error "--extension-registry must be provided at most once"
        | None -> loop { config with extension_registry = Some value } rest)
    | "--extension-registry" :: [] ->
        Error "--extension-registry requires a value"
    | "--extension-manifest" :: value :: rest -> (
        match config.extension.manifest with
        | Some _ -> Error "--extension-manifest must be provided at most once"
        | None ->
            loop
              {
                config with
                extension =
                  { config.extension with manifest = Some value };
              }
              rest)
    | "--extension-manifest" :: [] ->
        Error "--extension-manifest requires a value"
    | "--extension-executable" :: value :: rest -> (
        match config.extension.executable with
        | Some _ -> Error "--extension-executable must be provided at most once"
        | None ->
            loop
              {
                config with
                extension =
                  { config.extension with executable = Some value };
              }
              rest)
    | "--extension-executable" :: [] ->
        Error "--extension-executable requires a value"
    | "--extension-argument" :: value :: rest ->
        loop
          {
            config with
            extension =
              {
                config.extension with
                arguments_reversed =
                  value :: config.extension.arguments_reversed;
              };
          }
          rest
    | "--extension-argument" :: [] ->
        Error "--extension-argument requires a value"
    | "--extension-launch-path" :: value :: rest ->
        loop
          {
            config with
            extension =
              {
                config.extension with
                launch_paths_reversed =
                  value :: config.extension.launch_paths_reversed;
              };
          }
          rest
    | "--extension-launch-path" :: [] ->
        Error "--extension-launch-path requires a value"
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match
    loop
      {
        workspace = None;
        observation = None;
        extension_registry = None;
        extension =
          {
            manifest = None;
            executable = None;
            arguments_reversed = [];
            launch_paths_reversed = [];
          };
      }
      args
  with
  | Error _ as error -> error
  | Ok { workspace = None; _ } -> Error "--workspace is required"
  | Ok { observation = None; _ } -> Error "--observation is required"
  | Ok { extension_registry = Some _; extension = { manifest = Some _; _ }; _ }
  | Ok { extension_registry = Some _; extension = { executable = Some _; _ }; _ }
  | Ok
      {
        extension_registry = Some _;
        extension = { arguments_reversed = _ :: _; _ };
        _;
      } ->
      Error
        "--extension-registry is mutually exclusive with explicit extension options"
  | Ok
      {
        extension_registry = Some _;
        extension = { launch_paths_reversed = _ :: _; _ };
        _;
      } ->
      Error
        "--extension-registry is mutually exclusive with explicit extension options"
  | Ok { extension = { manifest = None; executable = Some _; _ }; _ } ->
      Error "--extension-executable requires --extension-manifest"
  | Ok { extension = { manifest = Some _; executable = None; _ }; _ } ->
      Error "--extension-manifest requires --extension-executable"
  | Ok
      {
        extension =
          {
            manifest = None;
            executable = None;
            arguments_reversed = _ :: _;
            _;
          };
        _;
      } ->
      Error "--extension-argument requires --extension-executable"
  | Ok
      {
        extension =
          {
            manifest = None;
            executable = None;
            launch_paths_reversed = _ :: _;
            _;
          };
        _;
      } ->
      Error "--extension-launch-path requires --extension-executable"
  | Ok
      {
        workspace = Some workspace;
        observation = Some encoded;
        extension;
        extension_registry;
      } ->
      Workspace_path.of_canonical_string encoded
      |> Result.map (fun observation ->
             (workspace, observation, extension, extension_registry))
      |> Result.map_error (fun message -> "invalid --observation: " ^ message)

let run_inspect args =
  match parse_inspect_args args with
  | Error message -> invalid_input ~command:"inspect" message
  | Ok (workspace, observation, { manifest = None; _ }, None) ->
      Workspace_inspect.inspect ~workspace ~observation
  | Ok (workspace, observation, { manifest = None; _ }, Some registry_file) -> (
      match read_extension_registry registry_file with
      | Error message -> invalid_input ~command:"inspect" message
      | Ok registry ->
          Workspace_inspect.inspect_with_registry ~workspace ~observation
            ~registry)
  | Ok
      ( workspace,
        observation,
        {
          manifest = Some manifest_file;
          executable = Some executable;
          arguments_reversed;
          launch_paths_reversed;
        }, None ) -> (
      match read_extension_manifest manifest_file with
      | Error message -> invalid_input ~command:"inspect" message
      | Ok manifest -> (
          match sandboxed_authority launch_paths_reversed with
          | Error message -> invalid_input ~command:"inspect" message
          | Ok authority ->
              Workspace_inspect.inspect_with_extension ~workspace ~observation
                ~manifest ~executable ~authority
                ~arguments:(List.rev arguments_reversed)))
  | Ok (_, _, _, _) ->
      invalid_input ~command:"inspect"
        "unreachable invalid extension configuration"

let parse_derive_args args =
  let rec loop (config : derive_config) = function
    | [] -> Ok config
    | "--workspace" :: value :: rest -> (
        match config.workspace with
        | Some _ -> Error "--workspace must be provided at most once"
        | None -> loop { config with workspace = Some value } rest)
    | "--workspace" :: [] -> Error "--workspace requires a value"
    | "--observation" :: value :: rest -> (
        match config.observation with
        | Some _ -> Error "--observation must be provided at most once"
        | None -> loop { config with observation = Some value } rest)
    | "--observation" :: [] -> Error "--observation requires a value"
    | "--annotation" :: value :: rest -> (
        match config.annotation with
        | Some _ -> Error "--annotation must be provided at most once"
        | None -> loop { config with annotation = Some value } rest)
    | "--annotation" :: [] -> Error "--annotation requires a value"
    | "--reference-definition" :: value :: rest -> (
        match config.reference_definition with
        | Some _ ->
            Error "--reference-definition must be provided at most once"
        | None ->
            loop { config with reference_definition = Some value } rest)
    | "--reference-definition" :: [] ->
        Error "--reference-definition requires a value"
    | "--target" :: value :: rest -> (
        match config.target with
        | Some _ -> Error "--target must be provided at most once"
        | None -> loop { config with target = Some value } rest)
    | "--target" :: [] -> Error "--target requires a value"
    | "--extension-registry" :: value :: rest -> (
        match config.extension_registry with
        | Some _ -> Error "--extension-registry must be provided at most once"
        | None -> loop { config with extension_registry = Some value } rest)
    | "--extension-registry" :: [] ->
        Error "--extension-registry requires a value"
    | "--deriver" :: value :: rest -> (
        match config.deriver with
        | Some _ -> Error "--deriver must be provided at most once"
        | None -> loop { config with deriver = Some value } rest)
    | "--deriver" :: [] -> Error "--deriver requires a value"
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match
    loop
      {
        workspace = None;
        observation = None;
        annotation = None;
        reference_definition = None;
        target = None;
        extension_registry = None;
        deriver = None;
      }
      args
  with
  | Error _ as error -> error
  | Ok { workspace = None; _ } -> Error "--workspace is required"
  | Ok { observation = None; _ } -> Error "--observation is required"
  | Ok { annotation = None; reference_definition = None; _ } ->
      Error "exactly one of --annotation or --reference-definition is required"
  | Ok { annotation = Some _; reference_definition = Some _; _ } ->
      Error "--annotation and --reference-definition are mutually exclusive"
  | Ok { target = None; _ } -> Error "--target is required"
  | Ok { target = Some target; _ } when not (String.equal target "sidecar") ->
      Error "--target must be sidecar"
  | Ok
      {
        workspace = Some workspace;
        observation = Some encoded;
        annotation;
        reference_definition;
        target = Some _;
        extension_registry;
        deriver;
      } ->
      let* observation =
        Workspace_path.of_canonical_string encoded
        |> Result.map_error (fun message -> "invalid --observation: " ^ message)
      in
      let* source =
        match annotation, reference_definition with
        | Some local, None ->
            Identifier.make local
            |> Result.map (fun local -> Workspace_derive.Annotation local)
            |> Result.map_error (fun message ->
                   "invalid --annotation: " ^ message)
        | None, Some local ->
            Identifier.make local
            |> Result.map (fun local ->
                   Workspace_derive.Reference_definition local)
            |> Result.map_error (fun message ->
                   "invalid --reference-definition: " ^ message)
        | None, None | Some _, Some _ ->
            Error "invalid derive source occurrence configuration"
      in
      let* deriver_name, deriver_version =
        match deriver with
        | None -> Ok ("inline-to-sidecar", "1")
        | Some identity -> (
            match String.split_on_char '@' identity with
            | [ name; version ] when name <> "" && version <> "" ->
                Ok (name, version)
            | _ -> Error "--deriver must be an exact name@version identity")
      in
      Ok
        ( workspace,
          observation,
          source,
          extension_registry,
          deriver_name,
          deriver_version )

let run_derive args =
  match parse_derive_args args with
  | Error message -> invalid_input ~command:"derive" message
  | Ok (workspace, observation, source, None, "inline-to-sidecar", "1") ->
      Workspace_derive.derive_sidecar ~workspace ~observation ~source
  | Ok (_, _, _, None, _, _) ->
      invalid_input ~command:"derive"
        "an installed Deriver requires --extension-registry"
  | Ok
      ( workspace,
        observation,
        source,
        Some registry_file,
        deriver_name,
        deriver_version ) -> (
      match read_extension_registry registry_file with
      | Error message -> invalid_input ~command:"derive" message
      | Ok registry ->
          Workspace_derive.derive_with_registry ~workspace ~observation
            ~source ~registry ~deriver_name ~deriver_version)

let parse_resolve_args args =
  let rec loop (config : resolve_config) = function
    | [] -> Ok config
    | "--workspace" :: value :: rest -> (
        match config.workspace with
        | Some _ -> Error "--workspace must be provided at most once"
        | None -> loop { config with workspace = Some value } rest)
    | "--workspace" :: [] -> Error "--workspace requires a value"
    | "--observation" :: value :: rest -> (
        match config.observation with
        | Some _ -> Error "--observation must be provided at most once"
        | None -> loop { config with observation = Some value } rest)
    | "--observation" :: [] -> Error "--observation requires a value"
    | "--reference" :: value :: rest -> (
        match config.reference with
        | Some _ -> Error "--reference must be provided at most once"
        | None -> loop { config with reference = Some value } rest)
    | "--reference" :: [] -> Error "--reference requires a value"
    | "--address" :: value :: rest -> (
        match config.address_file with
        | Some _ -> Error "--address must be provided at most once"
        | None -> loop { config with address_file = Some value } rest)
    | "--address" :: [] -> Error "--address requires a value"
    | "--observed-at" :: value :: rest -> (
        match config.observed_at with
        | Some _ -> Error "--observed-at must be provided at most once"
        | None -> loop { config with observed_at = Some value } rest)
    | "--observed-at" :: [] -> Error "--observed-at requires a value"
    | "--previous-snapshot" :: value :: rest -> (
        match config.previous_snapshot with
        | Some _ -> Error "--previous-snapshot must be provided at most once"
        | None -> loop { config with previous_snapshot = Some value } rest)
    | "--previous-snapshot" :: [] ->
        Error "--previous-snapshot requires a value"
    | "--extension-registry" :: value :: rest -> (
        match config.extension_registry with
        | Some _ -> Error "--extension-registry must be provided at most once"
        | None -> loop { config with extension_registry = Some value } rest)
    | "--extension-registry" :: [] ->
        Error "--extension-registry requires a value"
    | "--extension-manifest" :: value :: rest -> (
        match config.extension.manifest with
        | Some _ -> Error "--extension-manifest must be provided at most once"
        | None ->
            loop
              {
                config with
                extension =
                  { config.extension with manifest = Some value };
              }
              rest)
    | "--extension-manifest" :: [] ->
        Error "--extension-manifest requires a value"
    | "--extension-executable" :: value :: rest -> (
        match config.extension.executable with
        | Some _ -> Error "--extension-executable must be provided at most once"
        | None ->
            loop
              {
                config with
                extension =
                  { config.extension with executable = Some value };
              }
              rest)
    | "--extension-executable" :: [] ->
        Error "--extension-executable requires a value"
    | "--extension-argument" :: value :: rest ->
        loop
          {
            config with
            extension =
              {
                config.extension with
                arguments_reversed =
                  value :: config.extension.arguments_reversed;
              };
          }
          rest
    | "--extension-argument" :: [] ->
        Error "--extension-argument requires a value"
    | "--extension-launch-path" :: value :: rest ->
        loop
          {
            config with
            extension =
              {
                config.extension with
                launch_paths_reversed =
                  value :: config.extension.launch_paths_reversed;
              };
          }
          rest
    | "--extension-launch-path" :: [] ->
        Error "--extension-launch-path requires a value"
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match
    loop
      {
        workspace = None;
        observation = None;
        reference = None;
        address_file = None;
        observed_at = None;
        previous_snapshot = None;
        extension_registry = None;
        extension =
          {
            manifest = None;
            executable = None;
            arguments_reversed = [];
            launch_paths_reversed = [];
          };
      }
      args
  with
  | Error _ as error -> error
  | Ok { workspace = None; _ } -> Error "--workspace is required"
  | Ok { observed_at = None; _ } -> Error "--observed-at is required"
  | Ok
      {
        address_file = None;
        observation = None;
        reference = None;
        _;
      } ->
      Error
        "exactly one of --address or the --observation/--reference pair is required"
  | Ok { address_file = None; observation = None; reference = Some _; _ } ->
      Error "--reference requires --observation"
  | Ok { address_file = None; observation = Some _; reference = None; _ } ->
      Error "--observation requires --reference"
  | Ok { address_file = Some _; observation = Some _; _ }
  | Ok { address_file = Some _; reference = Some _; _ } ->
      Error "--address is mutually exclusive with --observation and --reference"
  | Ok { address_file = Some _; previous_snapshot = Some _; _ } ->
      Error "--previous-snapshot is valid only for a Reference"
  | Ok { extension_registry = Some _; extension = { manifest = Some _; _ }; _ }
  | Ok { extension_registry = Some _; extension = { executable = Some _; _ }; _ }
  | Ok
      {
        extension_registry = Some _;
        extension = { arguments_reversed = _ :: _; _ };
        _;
      } ->
      Error
        "--extension-registry is mutually exclusive with explicit extension options"
  | Ok
      {
        extension_registry = Some _;
        extension = { launch_paths_reversed = _ :: _; _ };
        _;
      } ->
      Error
        "--extension-registry is mutually exclusive with explicit extension options"
  | Ok { extension = { manifest = None; executable = Some _; _ }; _ } ->
      Error "--extension-executable requires --extension-manifest"
  | Ok { extension = { manifest = Some _; executable = None; _ }; _ } ->
      Error "--extension-manifest requires --extension-executable"
  | Ok
      {
        extension =
          {
            manifest = None;
            executable = None;
            arguments_reversed = _ :: _;
            _;
          };
        _;
      } ->
      Error "--extension-argument requires --extension-executable"
  | Ok
      {
        extension =
          { manifest = None; executable = None; launch_paths_reversed = _ :: _; _ };
        _;
      } ->
      Error "--extension-launch-path requires --extension-executable"
  | Ok
      {
        workspace = Some workspace;
        observation;
        reference;
        address_file;
        observed_at = Some observed_at;
        previous_snapshot;
        extension_registry;
        extension;
      } ->
      let* target =
        match address_file, observation, reference with
        | Some file, None, None ->
            read_region_address file
            |> Result.map (fun address -> Direct_address address)
        | None, Some encoded, Some reference ->
            Workspace_path.of_canonical_string encoded
            |> Result.map_error (fun message ->
                   "invalid --observation: " ^ message)
            |> Result.map (fun observation ->
                   Declared_reference { observation; reference })
        | _ -> Error "invalid resolve target configuration"
      in
      let* observed_at = Workspace_resolve.canonical_observed_at observed_at in
      let* previous_snapshot =
        match previous_snapshot with
        | None -> Ok None
        | Some file -> read_resolution_snapshot file |> Result.map Option.some
      in
      Ok
        ( workspace,
          target,
          observed_at,
          previous_snapshot,
          extension,
          extension_registry )

let run_resolve args =
  match parse_resolve_args args with
  | Error message -> invalid_input ~command:"resolve" message
  | Ok
      ( workspace,
        target,
        observed_at,
        previous_snapshot,
        { manifest = None; _ },
        None ) -> (
      match target with
      | Direct_address address ->
          Workspace_resolve.resolve_address ~workspace ~address ~observed_at
      | Declared_reference { observation; reference } ->
          Workspace_resolve.resolve_reference ~workspace ~observation
            ~reference ~observed_at ~previous_snapshot)
  | Ok
      ( workspace,
        target,
        observed_at,
        previous_snapshot,
        { manifest = None; _ },
        Some registry_file ) -> (
      match read_extension_registry registry_file with
      | Error message -> invalid_input ~command:"resolve" message
      | Ok registry -> (
          match target with
          | Direct_address address ->
              Workspace_resolve.resolve_address_with_registry ~workspace
                ~address ~observed_at ~registry
          | Declared_reference { observation; reference } ->
              Workspace_resolve.resolve_reference_with_registry ~workspace
                ~observation ~reference ~observed_at ~registry
                ~previous_snapshot))
  | Ok
      ( workspace,
        target,
        observed_at,
        previous_snapshot,
        {
          manifest = Some manifest_file;
          executable = Some executable;
          arguments_reversed;
          launch_paths_reversed;
        }, None ) -> (
      match read_extension_manifest manifest_file with
      | Error message -> invalid_input ~command:"resolve" message
      | Ok manifest -> (
          match sandboxed_authority launch_paths_reversed with
          | Error message -> invalid_input ~command:"resolve" message
          | Ok authority -> (
              let arguments = List.rev arguments_reversed in
              match target with
              | Direct_address address ->
                  Workspace_resolve.resolve_address_with_extension ~workspace
                    ~address ~observed_at ~manifest ~executable ~authority
                    ~arguments
              | Declared_reference { observation; reference } ->
                  Workspace_resolve.resolve_reference_with_extension ~workspace
                    ~observation ~reference ~observed_at ~manifest ~executable
                    ~authority ~arguments ~previous_snapshot)))
  | Ok _ ->
      invalid_input ~command:"resolve"
        "unreachable invalid extension configuration"

let related_help =
  {|Usage:
  monika related --workspace <dir> --observation <canonical-workspace-path>
    [--region <local-region-id> [--region-scope exact|contained]]
    [--direction incoming|outgoing|both] [--predicate <predicate>]
    [--limit <positive-integer>] [--json]
    [--extension-registry <file>]
    [--extension-manifest <file> --extension-executable <file>
      [--extension-argument <value>]...
      [--extension-launch-path <absolute-path>]...]

Returns explicit incoming and outgoing workspace relations. The default output
is Agent-readable text. --json returns the compact related-result schema.
|}

let parse_related_args args =
  let initial =
    {
      workspace = None;
      observation = None;
      region = None;
      region_scope = Workspace_graph.Contained;
      region_scope_set = false;
      direction = Workspace_graph.Both;
      direction_set = false;
      predicate = None;
      limit = 50;
      limit_set = false;
      json = false;
      extension_registry = None;
      extension =
        {
          manifest = None;
          executable = None;
          arguments_reversed = [];
          launch_paths_reversed = [];
        };
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
  let parse_region_scope = function
    | "exact" -> Ok Workspace_graph.Exact
    | "contained" -> Ok Workspace_graph.Contained
    | _ -> Error "--region-scope must be exact or contained"
  in
  let rec loop config = function
    | [] -> Ok config
    | "--workspace" :: value :: rest -> (
        match config.workspace with
        | Some _ -> Error "--workspace must be provided at most once"
        | None -> loop { config with workspace = Some value } rest)
    | "--workspace" :: [] -> Error "--workspace requires a value"
    | "--observation" :: value :: rest -> (
        match config.observation with
        | Some _ -> Error "--observation must be provided at most once"
        | None -> loop { config with observation = Some value } rest)
    | "--observation" :: [] -> Error "--observation requires a value"
    | "--region" :: value :: rest ->
        if Option.is_some config.region then
          Error "--region must be provided at most once"
        else loop { config with region = Some value } rest
    | "--region" :: [] -> Error "--region requires a value"
    | "--region-scope" :: value :: rest ->
        if config.region_scope_set then
          Error "--region-scope must be provided at most once"
        else
          Result.bind (parse_region_scope value) (fun region_scope ->
              loop { config with region_scope; region_scope_set = true } rest)
    | "--region-scope" :: [] -> Error "--region-scope requires a value"
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
    | "--extension-registry" :: value :: rest -> (
        match config.extension_registry with
        | Some _ -> Error "--extension-registry must be provided at most once"
        | None -> loop { config with extension_registry = Some value } rest)
    | "--extension-registry" :: [] ->
        Error "--extension-registry requires a value"
    | "--extension-manifest" :: value :: rest -> (
        match config.extension.manifest with
        | Some _ -> Error "--extension-manifest must be provided at most once"
        | None ->
            loop
              {
                config with
                extension =
                  { config.extension with manifest = Some value };
              }
              rest)
    | "--extension-manifest" :: [] ->
        Error "--extension-manifest requires a value"
    | "--extension-executable" :: value :: rest -> (
        match config.extension.executable with
        | Some _ -> Error "--extension-executable must be provided at most once"
        | None ->
            loop
              {
                config with
                extension =
                  { config.extension with executable = Some value };
              }
              rest)
    | "--extension-executable" :: [] ->
        Error "--extension-executable requires a value"
    | "--extension-argument" :: value :: rest ->
        loop
          {
            config with
            extension =
              {
                config.extension with
                arguments_reversed =
                  value :: config.extension.arguments_reversed;
              };
          }
          rest
    | "--extension-argument" :: [] ->
        Error "--extension-argument requires a value"
    | "--extension-launch-path" :: value :: rest ->
        loop
          {
            config with
            extension =
              {
                config.extension with
                launch_paths_reversed =
                  value :: config.extension.launch_paths_reversed;
              };
          }
          rest
    | "--extension-launch-path" :: [] ->
        Error "--extension-launch-path requires a value"
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  let* config = loop initial args in
  match (config.workspace, config.observation, config.extension) with
  | None, _, _ -> Error "--workspace is required"
  | _, None, _ -> Error "--observation is required"
  | _, _, _ when config.region_scope_set && Option.is_none config.region ->
      Error "--region-scope requires --region"
  | _, _, { manifest = None; executable = Some _; _ } ->
      Error "--extension-executable requires --extension-manifest"
  | _, _, { manifest = Some _; executable = None; _ } ->
      Error "--extension-manifest requires --extension-executable"
  | _, _,
    { manifest = None; executable = None; arguments_reversed = _ :: _; _ } ->
      Error "--extension-argument requires --extension-executable"
  | _, _,
    { manifest = None; executable = None; launch_paths_reversed = _ :: _; _ } ->
      Error "--extension-launch-path requires --extension-executable"
  | _, _, { manifest = Some _; _ } when Option.is_some config.extension_registry
    ->
      Error
        "--extension-registry is mutually exclusive with explicit extension options"
  | _, _, { executable = Some _; _ }
    when Option.is_some config.extension_registry ->
      Error
        "--extension-registry is mutually exclusive with explicit extension options"
  | _, _, { arguments_reversed = _ :: _; _ }
    when Option.is_some config.extension_registry ->
      Error
        "--extension-registry is mutually exclusive with explicit extension options"
  | _, _, { launch_paths_reversed = _ :: _; _ }
    when Option.is_some config.extension_registry ->
      Error
        "--extension-registry is mutually exclusive with explicit extension options"
  | Some workspace, Some encoded, _ ->
      let* observation =
        Workspace_path.of_canonical_string encoded
        |> Result.map_error (fun message -> "invalid --observation: " ^ message)
      in
      let* region =
        match config.region with
        | None -> Ok None
        | Some encoded ->
            Identifier.make encoded
            |> Result.map Option.some
            |> Result.map_error (fun message -> "invalid --region: " ^ message)
      in
      Ok (config, workspace, observation, region)

let run_related args =
  if args = [ "--help" ] then Ok (`Help related_help)
  else
    match parse_related_args args with
    | Error message -> Error (`Usage message)
    | Ok (config, workspace, observation, region) ->
        let query registry =
          match region with
          | None ->
              Workspace_graph.query_with_registry ~workspace ~observation
                ~direction:config.direction ~predicate:config.predicate
                ~limit:config.limit ~registry
          | Some region ->
              Workspace_graph.query_for_region_with_registry ~workspace
                ~observation ~region ~scope:config.region_scope
                ~direction:config.direction ~predicate:config.predicate
                ~limit:config.limit ~registry
        in
        (match config.extension with
        | { manifest = None; executable = None; _ }
          when Option.is_none config.extension_registry ->
            query Registry_snapshot.empty
        | { manifest = None; executable = None; _ } -> (
            match read_extension_registry (Option.get config.extension_registry) with
            | Error message -> Error (Workspace_graph.Usage message)
            | Ok registry -> query registry)
        | {
            manifest = Some manifest_file;
            executable = Some executable;
            arguments_reversed;
            launch_paths_reversed;
          } -> (
            match read_extension_manifest manifest_file with
            | Error message -> Error (Workspace_graph.Usage message)
            | Ok manifest -> (
                match
                  let* authority = sandboxed_authority launch_paths_reversed in
                  let* executable =
                    Extension_sandbox.resolve_executable executable
                  in
                  Installed_extension.make ~manifest ~executable
                    ~arguments:(List.rev arguments_reversed) ~authority
                  |> fun result ->
                  Result.bind result (fun extension ->
                      Registry_snapshot.make [ extension ])
                with
                | Error message -> Error (Workspace_graph.Usage message)
                | Ok registry -> query registry))
        | _ ->
            Error
              (Workspace_graph.Usage
                 "unreachable invalid extension configuration"))
        |> Result.map (fun result -> `Result (config.json, result))
        |> Result.map_error (function
             | Workspace_graph.Usage message -> `Usage message
             | Workspace_graph.Internal message -> `Internal message)

let read_help =
  {|Usage:
  monika read --workspace <dir> --observation <canonical-workspace-path>
    [--extension-registry <file>]
  monika read --workspace <dir> --observation <canonical-workspace-path>
    --extension-manifest <file> --extension-executable <file>
    [--extension-argument <value>]...
    [--extension-launch-path <absolute-path>]...

Renders one supported observation, its regions, references, annotations, and exact
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
    let finish path (inspected : Workspace_inspect.inspection) =
        let result = inspected.result in
        (match Command_result.termination result with
        | Command_result.Usage_failure message -> Error (`Usage message)
        | Command_result.Internal_failure _ ->
            Error (`Internal "workspace observation failed")
        | Command_result.Completed ->
            (match inspected.content with
            | None when Command_result.diagnostics result <> [] ->
                Error (`Diagnostics (Command_result.diagnostics result))
            | None -> Error (`Internal "interpreter returned no readable content")
            | Some _ -> Ok (`Result (Read_text.to_string ~path inspected))))
    in
    match parse_inspect_args args with
    | Error message -> Error (`Usage message)
    | Ok (workspace, path, { manifest = None; _ }, None) ->
        Workspace_inspect.inspect_observation ~workspace ~observation:path
        |> finish path
    | Ok (workspace, path, { manifest = None; _ }, Some registry_file) -> (
        match read_extension_registry registry_file with
        | Error message -> Error (`Usage message)
        | Ok registry ->
            Workspace_inspect.inspect_observation_with_registry ~workspace
              ~observation:path ~registry
            |> finish path)
    | Ok
        ( workspace,
          path,
          {
            manifest = Some manifest_file;
            executable = Some executable;
            arguments_reversed;
            launch_paths_reversed;
          }, None ) -> (
        match read_extension_manifest manifest_file with
        | Error message -> Error (`Usage message)
        | Ok manifest -> (
            match sandboxed_authority launch_paths_reversed with
            | Error message -> Error (`Usage message)
            | Ok authority ->
                Workspace_inspect.inspect_observation_with_extension ~workspace
                  ~observation:path ~manifest ~executable
                  ~arguments:(List.rev arguments_reversed) ~authority
                |> finish path))
    | Ok _ -> Error (`Internal "unreachable invalid extension configuration")

let parse_extension_test_args args =
  let rec loop (config : extension_test_config) = function
    | [] -> Ok config
    | "--manifest" :: value :: rest -> (
        match config.manifest with
        | Some _ -> Error "--manifest must be provided at most once"
        | None -> loop { config with manifest = Some value } rest)
    | "--manifest" :: [] -> Error "--manifest requires a value"
    | "--executable" :: value :: rest -> (
        match config.executable with
        | Some _ -> Error "--executable must be provided at most once"
        | None -> loop { config with executable = Some value } rest)
    | "--executable" :: [] -> Error "--executable requires a value"
    | "--argument" :: value :: rest ->
        loop
          {
            config with
            arguments_reversed = value :: config.arguments_reversed;
          }
          rest
    | "--argument" :: [] -> Error "--argument requires a value"
    | "--launch-path" :: value :: rest ->
        loop
          {
            config with
            launch_paths_reversed = value :: config.launch_paths_reversed;
          }
          rest
    | "--launch-path" :: [] -> Error "--launch-path requires a value"
    | "--resource-read-path" :: value :: rest ->
        loop
          {
            config with
            resource_read_paths_reversed =
              value :: config.resource_read_paths_reversed;
          }
          rest
    | "--resource-read-path" :: [] ->
        Error "--resource-read-path requires a value"
    | "--allow-network" :: rest ->
        if config.allow_network then
          Error "--allow-network must be provided at most once"
        else loop { config with allow_network = true } rest
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match
    loop
      {
        manifest = None;
        executable = None;
        arguments_reversed = [];
        launch_paths_reversed = [];
        resource_read_paths_reversed = [];
        allow_network = false;
      }
      args
  with
  | Error _ as error -> error
  | Ok { manifest = None; _ } -> Error "--manifest is required"
  | Ok { executable = None; arguments_reversed = _ :: _; _ } ->
      Error "--argument requires --executable"
  | Ok { executable = None; launch_paths_reversed = _ :: _; _ } ->
      Error "--launch-path requires --executable"
  | Ok { executable = None; resource_read_paths_reversed = _ :: _; _ } ->
      Error "--resource-read-path requires --executable"
  | Ok { executable = None; allow_network = true; _ } ->
      Error "--allow-network requires --executable"
  | Ok config -> Ok config

let extension_test_success manifest ~runtime_checked ~methods_checked =
  let summary =
    [
      ("checkedCapabilities", Command_result.Count 1);
      ( "protocolVersion",
        Command_result.Text (Extension_manifest.protocol_version manifest) );
    ]
    @ (if runtime_checked then [ ("runtimeChecked", Command_result.Flag true) ]
       else [])
    @
    match methods_checked with
    | None -> []
    | Some methods ->
        [ ("methodsChecked", Command_result.Count (List.length methods)) ]
  in
  match
    Command_result.make ~command:"extension-test"
      ~termination:Command_result.Completed ~effect:Command_result.No_change
      ~capabilities:[ Extension_manifest.capability manifest ] ~summary ()
  with
  | Ok result -> result
  | Error _ ->
      Command_result.internal_error ~command:"extension-test"
        ~error_code:"internal-invariant" ~operation:"construct-command-result"

let check_extension_runtime manifest executable arguments authority =
  match
    Extension_runtime.with_checked_session ~executable ~arguments ~authority
      ~limits:Extension_runtime.default_limits ~manifest (fun session ->
        match Extension_conformance.check ~session ~manifest with
        | Ok methods -> Ok (`Methods methods)
        | Error failure -> Ok (`Conformance_failure failure))
  with
  | Error failure -> Error (Extension_conformance.Session_runtime failure)
  | Ok (`Conformance_failure failure) -> Error failure
  | Ok (`Methods methods) -> Ok methods

let extension_test_failure manifest runtime_failure =
  match
    Extension_failure.make ~operation:Extension_failure.Session
      ~code:(Extension_runtime.failure_code runtime_failure)
      ~message:(Extension_runtime.failure_message runtime_failure)
      ?data:(Extension_runtime.failure_data runtime_failure) ()
  with
  | Error _ ->
      Command_result.internal_error ~command:"extension-test"
        ~error_code:"internal-invariant"
        ~operation:"construct-extension-failure"
  | Ok failure -> (
      match
        Diagnostic.make ~code:Diagnostic.Extension_failure
          ~message:(Extension_failure.message failure)
          ~extension_failure:failure ()
      with
      | Error _ ->
          Command_result.internal_error ~command:"extension-test"
            ~error_code:"internal-invariant"
            ~operation:"construct-extension-failure-diagnostic"
      | Ok diagnostic ->
          command_result ~command:"extension-test"
            ~termination:Command_result.Completed ~effect:Command_result.No_change
            ~diagnostics:[ diagnostic ]
            ~capabilities:[ Extension_manifest.capability manifest ] ())

let extension_test_conformance_failure manifest = function
  | Extension_conformance.Session_runtime failure ->
      extension_test_failure manifest failure
  | Extension_conformance.Method_runtime
      { operation; method_name; failure = runtime_failure } -> (
      match
        Extension_failure.make ~operation
          ~code:(Extension_runtime.failure_code runtime_failure)
          ~message:
            (method_name ^ ": "
           ^ Extension_runtime.failure_message runtime_failure)
          ?data:(Extension_runtime.failure_data runtime_failure) ()
      with
      | Error _ ->
          Command_result.internal_error ~command:"extension-test"
            ~error_code:"internal-invariant"
            ~operation:"construct-extension-method-failure"
      | Ok failure -> (
          match
            Diagnostic.make ~code:Diagnostic.Extension_failure
              ~message:(Extension_failure.message failure)
              ~extension_failure:failure ()
          with
          | Error _ ->
              Command_result.internal_error ~command:"extension-test"
                ~error_code:"internal-invariant"
                ~operation:"construct-extension-method-diagnostic"
          | Ok diagnostic ->
              command_result ~command:"extension-test"
                ~termination:Command_result.Completed
                ~effect:Command_result.No_change ~diagnostics:[ diagnostic ]
                ~capabilities:[ Extension_manifest.capability manifest ] ()))
  | Extension_conformance.Invalid_result { operation; method_name; message } -> (
      match
        Extension_failure.make ~operation ~code:"invalid-result"
          ~message:(method_name ^ ": " ^ message) ()
      with
      | Error _ ->
          Command_result.internal_error ~command:"extension-test"
            ~error_code:"internal-invariant"
            ~operation:"construct-extension-conformance-failure"
      | Ok failure -> (
          match
            Diagnostic.make ~code:Diagnostic.Extension_failure
              ~message:(Extension_failure.message failure)
              ~extension_failure:failure ()
          with
          | Error _ ->
              Command_result.internal_error ~command:"extension-test"
                ~error_code:"internal-invariant"
                ~operation:"construct-extension-conformance-diagnostic"
          | Ok diagnostic ->
              command_result ~command:"extension-test"
                ~termination:Command_result.Completed
                ~effect:Command_result.No_change ~diagnostics:[ diagnostic ]
                ~capabilities:[ Extension_manifest.capability manifest ] ()))

let run_extension_test args =
  match parse_extension_test_args args with
  | Error message -> invalid_input ~command:"extension-test" message
  | Ok ({ manifest = Some manifest_file; _ } as config) -> (
      match read_extension_manifest manifest_file with
      | Error message -> invalid_input ~command:"extension-test" message
      | Ok manifest -> (
          match config.executable with
          | None ->
              extension_test_success manifest ~runtime_checked:false
                ~methods_checked:None
          | Some executable ->
              let arguments = List.rev config.arguments_reversed in
              let capability = Extension_manifest.capability manifest in
              let authority =
                match Capability.kind capability with
                | Capability.Resource_observer ->
                    Extension_authority.resource_observer
                      ~launch_paths:(List.rev config.launch_paths_reversed)
                      ~resource_read_paths:
                        (List.rev config.resource_read_paths_reversed)
                      ~network:config.allow_network
                | _ ->
                    if
                      config.allow_network
                      || config.resource_read_paths_reversed <> []
                    then
                      Error
                        "resource observation authority is valid only for a Resource Observer"
                    else
                      sandboxed_authority config.launch_paths_reversed
              in
              (match authority with
              | Error message -> invalid_input ~command:"extension-test" message
              | Ok authority -> (
                  match
                    check_extension_runtime manifest executable arguments
                      authority
                  with
                  | Ok methods ->
                      extension_test_success manifest ~runtime_checked:true
                        ~methods_checked:(Some methods)
                  | Error failure ->
                      extension_test_conformance_failure manifest failure))))
  | Ok { manifest = None; _ } ->
      invalid_input ~command:"extension-test" "--manifest is required"

let run_capabilities args =
  let rec parse registry = function
    | [] -> Ok registry
    | "--extension-registry" :: value :: rest -> (
        match registry with
        | Some _ -> Error "--extension-registry must be provided at most once"
        | None -> parse (Some value) rest)
    | "--extension-registry" :: [] ->
        Error "--extension-registry requires a value"
    | flag :: _ when String.length flag >= 2 && String.sub flag 0 2 = "--" ->
        Error ("unknown option: " ^ flag)
    | value :: _ -> Error ("unexpected positional argument: " ^ value)
  in
  match parse None args with
  | Error message -> invalid_input ~command:"capabilities" message
  | Ok None -> Built_in_capabilities.command_result ()
  | Ok (Some file) -> (
      match read_extension_registry file with
      | Error message -> invalid_input ~command:"capabilities" message
      | Ok registry -> (
          match Built_in_capabilities.with_registry registry with
          | Error message -> invalid_input ~command:"capabilities" message
          | Ok capabilities ->
              command_result ~command:"capabilities"
                ~termination:Command_result.Completed
                ~effect:Command_result.No_change ~capabilities
                ~summary:
                  [
                    ( "capabilities",
                      Command_result.Count (List.length capabilities) );
                  ]
                ()))

let main argv =
  match argv with
  | _program :: "scan" :: args -> run_scan args
  | _program :: "inspect" :: args -> run_inspect args
  | _program :: "check" :: args -> run_check args
  | _program :: "derive" :: args -> run_derive args
  | _program :: "resolve" :: args -> run_resolve args
  | _program :: "capabilities" :: args -> run_capabilities args
  | _program :: "extension" :: "test" :: args -> run_extension_test args
  | _program :: "extension" :: _ ->
      invalid_input ~command:"extension-test" "extension subcommand must be test"
  | _program :: "apply" :: args -> run_apply args
  | _program :: [] -> invalid_input ~command:"monika" "command is required"
  | _program :: command :: _ ->
      invalid_input ~command:"monika" ("unknown command: " ^ command)
  | [] -> invalid_input ~command:"monika" "command is required"

let run argv =
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
          exit
            (match Workspace_graph.result_status result with
            | Workspace_graph.Failed -> 1
            | Workspace_graph.Complete -> 0
            | Workspace_graph.Incomplete ->
                if
                  Workspace_graph.diagnostics result
                  |> List.exists (fun diagnostic ->
                         Diagnostic.effective_severity diagnostic
                         = Diagnostic.Error)
                then 1
                else 0)
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

let () =
  let argv = Sys.argv |> Array.to_list in
  match Command_boundary.protect (fun () -> run argv) with
  | Ok () -> ()
  | Error result ->
      print_result result;
      exit (process_exit_code result)
