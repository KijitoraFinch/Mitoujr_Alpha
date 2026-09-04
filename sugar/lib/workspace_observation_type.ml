type known = Markdown | Yaml | Jsonl

let infer path =
  match List.rev (Workspace_path.segments path) with
  | [] -> None
  | basename :: _ when Filename.check_suffix basename ".md" ->
      Some Markdown
  | basename :: _ when Filename.check_suffix basename ".markdown" ->
      Some Markdown
  | basename :: _ when Filename.check_suffix basename ".yaml" ->
      Some Yaml
  | basename :: _ when Filename.check_suffix basename ".yml" ->
      Some Yaml
  | basename :: _ when Filename.check_suffix basename ".jsonl" ->
      Some Jsonl
  | basename :: _ when Filename.check_suffix basename ".ndjson" ->
      Some Jsonl
  | _ -> None

let inferred_name path =
  match infer path with
  | None -> None
  | Some Markdown -> Some "text/markdown"
  | Some Yaml -> Some "application/yaml"
  | Some Jsonl -> Some "application/x-ndjson"

let classify path =
  match infer path with
  | None -> Observation_type.binary
  | Some Markdown -> Observation_type.markdown
  | Some Yaml -> Observation_type.yaml
  | Some Jsonl -> Observation_type.jsonl
