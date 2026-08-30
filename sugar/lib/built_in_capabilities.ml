let make ?(version = "1") ?applies_to ?schemas kind name =
  Capability.make ~kind ~name ~version ?applies_to ?schemas ()

let observation_type name =
  Observation_type.make ~name ~version:"1" () |> Result.get_ok

let observation_types values =
  Capability.{ observation_types = values; path_globs = [] }

let no_observation_types = observation_types []

let schemas ?(selectors = []) result =
  Capability.{ selector_schemas = selectors; result_schemas = [ result ] }

let schema name = "https://monika.local/schemas/" ^ name ^ ".schema.json"

let all =
  let ( let* ) = Result.bind in
  let* workspace_file =
    make ~version:"3" ~applies_to:no_observation_types
      ~schemas:(schemas (schema "observation"))
      Capability.Resource_observer "workspace-file"
  in
  let* markdown =
    make
      ~applies_to:(observation_types [ Observation_type.markdown ])
      ~schemas:(schemas (schema "interpretation")) Capability.Interpreter "markdown"
  in
  let* jsonl =
    make
      ~applies_to:
        (observation_types [ observation_type "application/x-ndjson" ])
      ~schemas:(schemas (schema "interpretation")) Capability.Interpreter "jsonl"
  in
  let* markdown_comment =
    make
      ~applies_to:(observation_types [ Observation_type.markdown ])
      ~schemas:(schemas (schema "annotation-extraction"))
      Capability.Annotation_extractor "markdown-html-comment"
  in
  let* markdown_link =
    make
      ~applies_to:(observation_types [ Observation_type.markdown ])
      ~schemas:(schemas (schema "annotation-extraction"))
      Capability.Annotation_extractor "markdown-inline-link"
  in
  let* markdown_reference =
    make ~applies_to:(observation_types [ Observation_type.markdown ])
      ~schemas:(schemas (schema "reference-extraction"))
      Capability.Reference_extractor "markdown-inline-reference"
  in
  let* deriver =
    make ~applies_to:no_observation_types
      ~schemas:(schemas (schema "proposed-patch-list")) Capability.Deriver
      "inline-to-sidecar"
  in
  let* auditor =
    make ~applies_to:no_observation_types
      ~schemas:(schemas (schema "diagnostic-list")) Capability.Auditor
      "workspace-check"
  in
  Ok
    [
      workspace_file;
      markdown;
      jsonl;
      markdown_comment;
      markdown_link;
      markdown_reference;
      deriver;
      auditor;
    ]

let with_registry registry =
  let ( let* ) = Result.bind in
  let* built_in = all in
  let installed =
    Registry_snapshot.extensions registry
    |> List.map Installed_extension.capability
  in
  let capabilities = List.sort Capability.compare (built_in @ installed) in
  let rec reject_collision = function
    | left :: (right :: _)
      when Capability.compare left right = 0 ->
        Error
          (Printf.sprintf
             "installed capability identity collides with built-in %s/%s/%s"
             (Capability.kind_string (Capability.kind left))
             (Capability.name left) (Capability.version left))
    | _ :: rest -> reject_collision rest
    | [] -> Ok capabilities
  in
  reject_collision capabilities

let command_result () =
  match all with
  | Error _ ->
      Command_result.internal_error ~command:"capabilities"
        ~error_code:"internal-invariant" ~operation:"construct-capabilities"
  | Ok capabilities -> (
      match
        Command_result.make ~command:"capabilities"
          ~termination:Command_result.Completed ~effect:Command_result.No_change
          ~capabilities
          ~summary:
            [ ("capabilities", Command_result.Count (List.length capabilities)) ]
          ()
      with
      | Ok result -> result
      | Error _ ->
          Command_result.internal_error ~command:"capabilities"
            ~error_code:"internal-invariant"
            ~operation:"construct-command-result")
