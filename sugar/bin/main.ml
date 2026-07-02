open Monika_sugar

type apply_config = {
  workspace : string option;
  patch_file : string option;
  dry_run : bool;
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

let parse_apply_args args =
  let rec loop config = function
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

let main argv =
  match argv with
  | _program :: "apply" :: args -> run_apply args
  | _program :: [] -> invalid_input ~command:"monika" "command is required"
  | _program :: command :: _ ->
      invalid_input ~command:"monika" ("unknown command: " ^ command)
  | [] -> invalid_input ~command:"monika" "command is required"

let () = Sys.argv |> Array.to_list |> main |> print_result
