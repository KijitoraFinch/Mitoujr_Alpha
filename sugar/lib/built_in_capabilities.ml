let make ?(version = "1") ?applies_to kind name =
  Capability.make ~kind ~name ~version ?applies_to ()

let media_types values =
  Capability.{ media_types = values; path_globs = [] }

let all =
  let ( let* ) = Result.bind in
  let* workspace_file =
    make ~version:"3" Capability.Observation_provider "workspace-file"
  in
  let* markdown =
    make ~applies_to:(media_types [ "text/markdown" ]) Capability.Interpreter
      "markdown"
  in
  let* sidecar =
    make
      ~applies_to:(media_types [ "application/yaml"; "text/yaml" ])
      Capability.Interpreter "sidecar-v1"
  in
  let* jsonl =
    make ~applies_to:(media_types [ "application/x-ndjson" ]) Capability.Interpreter
      "jsonl"
  in
  let* markdown_comment =
    make ~applies_to:(media_types [ "text/markdown" ]) Capability.Annotation_extractor
      "markdown-html-comment"
  in
  let* markdown_link =
    make ~applies_to:(media_types [ "text/markdown" ]) Capability.Annotation_extractor
      "markdown-inline-link"
  in
  let* sidecar_extractor =
    make
      ~applies_to:(media_types [ "application/yaml"; "text/yaml" ])
      Capability.Annotation_extractor "sidecar-v1"
  in
  let* deriver = make Capability.Deriver "inline-to-sidecar" in
  let* auditor = make Capability.Auditor "workspace-check" in
  Ok
    [
      workspace_file;
      markdown;
      sidecar;
      jsonl;
      markdown_comment;
      markdown_link;
      sidecar_extractor;
      deriver;
      auditor;
    ]

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
