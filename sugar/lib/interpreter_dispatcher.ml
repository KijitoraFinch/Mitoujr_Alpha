type selected =
  | Built_in_markdown
  | Built_in_jsonl
  | Built_in_sidecar_v1
  | Installed of Installed_extension.t

let ( let* ) = Result.bind

let interpreter name =
  Interpreter.make ~name ~version:"1" ()
  |> Result.get_ok

let markdown = interpreter "markdown"
let jsonl = interpreter "jsonl"
let sidecar_v1 = interpreter "sidecar-v1"

let identity = function
  | Built_in_markdown -> markdown
  | Built_in_jsonl -> jsonl
  | Built_in_sidecar_v1 -> sidecar_v1
  | Installed extension ->
      let capability = Installed_extension.capability extension in
      Interpreter.make ~name:(Capability.name capability)
        ~version:(Capability.version capability) ()
      |> Result.get_ok

let built_in_for_observation observation =
  let observation_type = Observation.observation_type observation in
  match Observation_type.name observation_type, Observation_type.version observation_type with
  | "text/markdown", "1" -> Some Built_in_markdown
  | _ -> None

let installed_candidates registry observation =
  Registry_snapshot.extensions registry
  |> List.fold_left
       (fun result extension ->
         let* candidates = result in
         let capability = Installed_extension.capability extension in
         if Capability.kind capability <> Capability.Interpreter then
           Ok candidates
         else
           let* accepts = Extension_applicability.accepts capability ~observation in
           Ok (if accepts then Installed extension :: candidates else candidates))
       (Ok [])

let selected_name selected =
  let value = identity selected in
  Interpreter.name value ^ "@" ^ Interpreter.version value

let select registry observation =
  let* installed = installed_candidates registry observation in
  let candidates =
    match built_in_for_observation observation with
    | None -> installed
    | Some built_in -> built_in :: installed
  in
  match List.rev candidates with
  | [] -> Ok None
  | [ selected ] -> Ok (Some selected)
  | candidates ->
      let names = candidates |> List.map selected_name |> String.concat ", " in
      Error ("multiple interpreters apply to the fixed observation: " ^ names)

let find_exact registry interpreter =
  let built_in =
    if Interpreter.equal interpreter markdown then Some Built_in_markdown
    else if Interpreter.equal interpreter jsonl then Some Built_in_jsonl
    else if Interpreter.equal interpreter sidecar_v1 then Some Built_in_sidecar_v1
    else None
  in
  let installed = Registry_snapshot.find_interpreter registry interpreter in
  match built_in, installed with
  | Some _, Some _ ->
      Error
        (Printf.sprintf
           "installed interpreter identity collides with built-in %s@%s"
           (Interpreter.name interpreter) (Interpreter.version interpreter))
  | Some selected, None -> Ok (Some selected)
  | None, Some extension -> Ok (Some (Installed extension))
  | None, None -> Ok None

let associated_types registry path =
  Registry_snapshot.extensions registry
  |> List.fold_left
       (fun result extension ->
         let* types = result in
         let capability = Installed_extension.capability extension in
         if Capability.kind capability <> Capability.Interpreter then Ok types
         else
           let* association = Extension_applicability.associate capability ~path in
           match association with
           | Extension_applicability.Not_associated -> Ok types
           | Extension_applicability.Associated observation_type ->
               Ok (observation_type :: types))
       (Ok [])

let classify_path registry path =
  let* associated = associated_types registry path in
  match associated with
  | [] -> Ok (Workspace_observation_type.classify path)
  | first :: rest ->
      if List.for_all (Observation_type.equal first) rest then Ok first
      else
        let names =
          associated
          |> List.map (fun value ->
                 Observation_type.name value ^ "@" ^ Observation_type.version value)
          |> List.sort_uniq String.compare |> String.concat ", "
        in
        Error ("installed interpreters assign conflicting observation types: " ^ names)
