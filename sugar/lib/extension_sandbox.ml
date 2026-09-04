type allowed_path = { path : string; directory : bool }

type prepared = {
  executable : string;
  arguments : string array;
  environment : string array;
  scratch : string;
}

let ( let* ) = Result.bind

external platform : unit -> string = "monika_sugar_extension_platform"

let scratch_limit_bytes = 16 * 1024 * 1024
let linux_scratch_path = "/.monika-extension-scratch"

let path_separator = if Sys.win32 then ';' else ':'

let executable_from_path executable =
  let executable_candidate directory =
    Filename.concat directory executable
  in
  let rec find = function
    | [] -> Error "extension executable was not found in PATH"
    | directory :: rest ->
        let candidate = executable_candidate directory in
        if
          Sys.file_exists candidate
          &&
          try
            Unix.access candidate [ Unix.X_OK ];
            true
          with Unix.Unix_error _ -> false
        then Ok candidate
        else find rest
  in
  match Sys.getenv_opt "PATH" with
  | None -> Error "PATH is unavailable while resolving extension executable"
  | Some path -> String.split_on_char path_separator path |> find

let resolve_executable executable =
  let* candidate =
    if Filename.is_relative executable then
      if String.contains executable Filename.dir_sep.[0] then
        Ok (Filename.concat (Sys.getcwd ()) executable)
      else executable_from_path executable
    else Ok executable
  in
  try
    let path = Unix.realpath candidate in
    Unix.access path [ Unix.X_OK ];
    if (Unix.stat path).Unix.st_kind <> Unix.S_REG then
      Error "extension executable must resolve to a regular file"
    else Ok path
  with Unix.Unix_error _ | Sys_error _ ->
    Error "extension executable could not be resolved as an executable file"

let resolve_allowed_path path =
  try
    let path = Unix.realpath path in
    let kind = (Unix.stat path).Unix.st_kind in
    match kind with
    | Unix.S_REG -> Ok { path; directory = false }
    | Unix.S_DIR -> Ok { path; directory = true }
    | _ -> Error "extension authority path must resolve to a regular file or directory"
  with Unix.Unix_error _ | Sys_error _ ->
    Error "extension authority path could not be resolved"

let collect_allowed_paths authority =
  Extension_authority.launch_paths authority
  @ Extension_authority.resource_read_paths authority
  |> List.map resolve_allowed_path
  |> fun items ->
  List.fold_right
    (fun item result ->
      let* item = item in
      let* result = result in
      Ok (item :: result))
    items (Ok [])
  |> Result.map (List.sort_uniq (fun left right -> String.compare left.path right.path))

let path_is_within ~root path =
  String.equal root path
  ||
  let prefix = root ^ Filename.dir_sep in
  String.length path > String.length prefix
  && String.starts_with ~prefix path

let trusted_macos_runtime_roots =
  [
    "/Applications";
    "/Library/Developer";
    "/nix/store";
    "/opt/homebrew";
    "/opt/local";
    "/usr/local";
  ]

let executable_access executable =
  let directory = Filename.dirname executable in
  let runtime_root = Filename.dirname directory in
  if
    String.equal (platform ()) "darwin"
    && String.equal (Filename.basename directory) "bin"
    && List.exists
         (fun trusted ->
           not (String.equal trusted runtime_root)
           && path_is_within ~root:trusted runtime_root)
         trusted_macos_runtime_roots
  then { path = runtime_root; directory = true }
  else { path = executable; directory = false }

let make_scratch () =
  try
    let path = Filename.temp_file "monika-extension-scratch-" "" in
    Sys.remove path;
    Unix.mkdir path 0o700;
    Ok (Unix.realpath path)
  with Unix.Unix_error _ | Sys_error _ ->
    Error "could not create bounded extension scratch space"

let rec remove_tree path =
  try
    match (Unix.lstat path).Unix.st_kind with
    | Unix.S_DIR ->
        Sys.readdir path
        |> Array.iter (fun name -> remove_tree (Filename.concat path name));
        Unix.rmdir path
    | _ -> Unix.unlink path
  with Unix.Unix_error _ | Sys_error _ -> ()

let sandbox_parameter name value = [ "-D"; name ^ "=" ^ value ]

let macos_profile executable allowed =
  let rules =
    allowed
    |> List.mapi (fun index value ->
           let parameter = Printf.sprintf "READ%d" index in
           let filter = if value.directory then "subpath" else "literal" in
           (parameter, Printf.sprintf "(%s (param \"%s\"))" filter parameter))
  in
  let filters = List.map snd rules |> String.concat " " in
  let executable_filter =
    if executable.directory then "subpath" else "literal"
  in
  let profile =
    String.concat " "
      [
        "(version 1)";
        "(deny default)";
        "(import \"system.sb\")";
        (Printf.sprintf
           "(allow file-read* file-map-executable (%s (param \"EXECUTABLE\"))"
           executable_filter);
        filters ^ ")";
        (Printf.sprintf "(allow process-exec (%s (param \"EXECUTABLE\")))"
           executable_filter);
        "(allow file-read* file-write* (subpath (param \"SCRATCH\")))";
      ]
  in
  (profile, List.map fst rules)

let macos_command ~target ~arguments ~authority ~allowed ~scratch =
  let executable_access = executable_access target in
  let profile, parameter_names = macos_profile executable_access allowed in
  let definitions =
    sandbox_parameter "EXECUTABLE" executable_access.path
    @ sandbox_parameter "SCRATCH" scratch
    @ List.concat
        (List.map2
           (fun name value -> sandbox_parameter name value.path)
           parameter_names allowed)
  in
  let network_rule =
    if Extension_authority.network authority then "(allow network*)"
    else "(deny network*)"
  in
  let profile = profile ^ " " ^ network_rule in
  let executable = "/usr/bin/sandbox-exec" in
  if not (Sys.file_exists executable) then
    Error "macOS sandbox-exec is unavailable; refusing unsandboxed Extension execution"
  else
    Ok
      ( executable,
        Array.of_list
          (executable :: "-p" :: profile :: definitions @ (target :: arguments)) )

let path_ancestors path =
  let rec collect current values =
    let parent = Filename.dirname current in
    if String.equal current parent || String.equal parent "/" then values
    else collect parent (parent :: values)
  in
  collect path []

let compact_bind_roots roots =
  let compare_root left right =
    let by_length = Int.compare (String.length left.path) (String.length right.path) in
    if by_length <> 0 then by_length else String.compare left.path right.path
  in
  roots |> List.sort compare_root
  |> List.fold_left
       (fun retained candidate ->
         if
           List.exists
             (fun root -> root.directory && path_is_within ~root:root.path candidate.path)
             retained
         then retained
         else candidate :: retained)
       []
  |> List.rev

let linux_system_entry path =
  try
    match (Unix.lstat path).Unix.st_kind with
    | Unix.S_LNK -> [ "--symlink"; Unix.readlink path; path ]
    | Unix.S_DIR | Unix.S_REG -> [ "--ro-bind"; path; path ]
    | _ -> []
  with Unix.Unix_error _ | Sys_error _ -> []

let linux_system_roots () =
  [ "/usr"; "/bin"; "/lib"; "/lib64" ]
  |> List.filter_map (fun path ->
         try
           match (Unix.stat path).Unix.st_kind with
           | Unix.S_DIR -> Some { path = Unix.realpath path; directory = true }
           | _ -> None
         with Unix.Unix_error _ | Sys_error _ -> None)
  |> compact_bind_roots

let linux_runtime_files =
  [
    "/etc/ld.so.cache";
    "/etc/resolv.conf";
    "/etc/nsswitch.conf";
    "/etc/hosts";
    "/etc/gai.conf";
  ]

let linux_runtime_directories =
  [ "/etc/ssl"; "/etc/pki"; "/etc/ca-certificates" ]

let unique_directories paths =
  paths |> List.sort_uniq String.compare
  |> List.sort (fun left right ->
         let by_length = Int.compare (String.length left) (String.length right) in
         if by_length <> 0 then by_length else String.compare left right)

let linux_bind_arguments ~system_roots roots =
  let roots =
    compact_bind_roots roots
    |> List.filter (fun value ->
           not
             (List.exists
                (fun system ->
                  path_is_within ~root:system.path value.path)
                system_roots))
  in
  let directories =
    roots |> List.concat_map (fun value -> path_ancestors value.path)
    |> List.filter (fun path ->
           not
             (List.exists
                (fun system -> path_is_within ~root:system.path path)
                system_roots))
    |> unique_directories
    |> List.concat_map (fun path -> [ "--dir"; path ])
  in
  directories
  @ List.concat_map
      (fun value -> [ "--ro-bind"; value.path; value.path ])
      roots

let linux_command ~target ~arguments ~authority ~allowed =
  let executable = "/usr/bin/bwrap" in
  if not (Sys.file_exists executable) then
    Error
      "Linux bubblewrap is unavailable; refusing unsandboxed Extension execution"
  else if
    path_is_within ~root:linux_scratch_path target
    || List.exists
         (fun value -> path_is_within ~root:linux_scratch_path value.path)
         allowed
  then Error "Extension launch path collides with the reserved sandbox scratch path"
  else
    let runtime_directories =
      linux_runtime_directories
      |> List.filter_map (fun path ->
             try
               if (Unix.stat path).Unix.st_kind = Unix.S_DIR then
                 Some { path = Unix.realpath path; directory = true }
               else None
             with Unix.Unix_error _ | Sys_error _ -> None)
    in
    let system_roots =
      compact_bind_roots (linux_system_roots () @ runtime_directories)
    in
    let system =
      [ "/usr"; "/bin"; "/lib"; "/lib64" ]
      @ linux_runtime_directories
      |> List.sort_uniq String.compare
      |> List.concat_map linux_system_entry
    in
    let runtime_files =
      linux_runtime_files
      |> List.filter_map (fun path ->
             try
               if (Unix.stat path).Unix.st_kind = Unix.S_REG then
                 Some { path; directory = false }
               else None
             with Unix.Unix_error _ | Sys_error _ -> None)
    in
    let extension_paths =
      executable_access target :: allowed
    in
    let binds =
      linux_bind_arguments ~system_roots (runtime_files @ extension_paths)
    in
    let network =
      if Extension_authority.network authority then [ "--share-net" ] else []
    in
    let options =
      [
        "--die-with-parent";
        "--new-session";
        "--unshare-all";
      ]
      @ network @ [ "--dir"; "/etc" ] @ system @ binds
      @ [
          "--cap-drop";
          "ALL";
          "--dev";
          "/dev";
          "--proc";
          "/proc";
          "--size";
          string_of_int scratch_limit_bytes;
          "--tmpfs";
          linux_scratch_path;
          "--chdir";
          linux_scratch_path;
          "--";
        ]
    in
    Ok
      ( executable,
        Array.of_list (executable :: options @ (target :: arguments)) )

let environment scratch =
  [|
    "HOME=" ^ scratch;
    "TMPDIR=" ^ scratch;
    "TMP=" ^ scratch;
    "TEMP=" ^ scratch;
    "MONIKA_SCRATCH=" ^ scratch;
    "PATH=/usr/bin:/bin";
    "LANG=C.UTF-8";
    "LC_ALL=C.UTF-8";
    "TZ=UTC";
  |]

let prepare ~executable ~arguments ~authority =
  let* target = resolve_executable executable in
  let* allowed = collect_allowed_paths authority in
  let* scratch = make_scratch () in
  let command =
    match platform () with
    | "darwin" ->
        macos_command ~target ~arguments ~authority ~allowed ~scratch
    | "linux" -> linux_command ~target ~arguments ~authority ~allowed
    | "windows" ->
        Error
          "Windows Extension sandbox is unavailable; refusing unsandboxed Extension execution"
    | _ ->
        Error
          "Extension sandbox is unavailable on this platform; refusing unsandboxed execution"
  in
  match command with
  | Error _ as error ->
      remove_tree scratch;
      error
  | Ok (executable, arguments) ->
      let environment_scratch =
        if String.equal (platform ()) "linux" then linux_scratch_path
        else scratch
      in
      Ok
        {
          executable;
          arguments;
          environment = environment environment_scratch;
          scratch;
        }

let executable value = value.executable
let arguments value = value.arguments
let environment value = value.environment
let scratch value = value.scratch
let cleanup value = remove_tree value.scratch
