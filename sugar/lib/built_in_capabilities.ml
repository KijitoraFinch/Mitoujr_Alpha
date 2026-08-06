let make ?(version = "1") ?applies_to kind name =
  Capability.make ~kind ~name ~version ?applies_to () |> Result.get_ok

let media_types values =
  Capability.{ media_types = values; path_globs = [] }

let all =
  [
    make ~version:"2" Capability.Artifact_provider "workspace-file";
    make ~applies_to:(media_types [ "text/markdown" ]) Capability.Interpreter
      "markdown";
    make
      ~applies_to:(media_types [ "application/yaml"; "text/yaml" ])
      Capability.Interpreter "sidecar-v1";
    make ~applies_to:(media_types [ "application/x-ndjson" ])
      Capability.Interpreter "jsonl";
    make ~applies_to:(media_types [ "text/markdown" ])
      Capability.Annotation_extractor "markdown-html-comment";
    make ~applies_to:(media_types [ "text/markdown" ])
      Capability.Annotation_extractor "markdown-inline-link";
    make
      ~applies_to:(media_types [ "application/yaml"; "text/yaml" ])
      Capability.Annotation_extractor "sidecar-v1";
    make Capability.Deriver "inline-to-sidecar";
    make Capability.Auditor "workspace-check";
  ]

let command_result () =
  Command_result.make ~command:"capabilities"
    ~termination:Command_result.Completed ~effect:Command_result.No_change
    ~capabilities:all
    ~summary:[ ("capabilities", Command_result.Count (List.length all)) ] ()
  |> Result.get_ok
