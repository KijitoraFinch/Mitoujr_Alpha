type resolved = {
  observation_identity : Observation_identity.t;
  content_identity : Content_identity.t;
  region_fingerprint : string option;
  display : string option;
}

type outcome =
  | Resolved of resolved
  | Not_found
  | Invalid_selector of string
  | Read_failure

let known_region regions id =
  List.find_opt (fun region -> Region_id.equal id (Region.id region)) regions

let resolved ?region_fingerprint ?display observation_identity content_identity =
  Resolved
    { observation_identity; content_identity; region_fingerprint; display }

let target_path reference =
  match Reference.target_origin (Reference.target reference) with
  | Origin.Workspace path -> Ok path
  | _ -> Error "only workspace reference targets are supported"

let resolve ~workspace ~regions reference =
  match target_path reference with
  | Error message -> Invalid_selector message
  | Ok path -> (
      match Workspace_read.read ~workspace ~path with
      | Error Workspace_read.Missing_file -> Not_found
      | Error _ -> Read_failure
      | Ok file ->
          let content_identity = Workspace_read.content_identity file in
          let observation_type = Workspace_observation_type.classify path in
          let identity =
            content_identity |> Observation_identity.of_content
                 ~observation_type
          in
          let content = Workspace_read.content file in
          match Reference.target_selector (Reference.target reference) with
          | Selector.Whole_observation -> resolved identity content_identity
          | Selector.Text_range range ->
              if Text_range.end_ range <= String.length content then
                let selected =
                  String.sub content (Text_range.start range)
                    (Text_range.length range)
                in
                resolved
                  ~region_fingerprint:
                    (Content_digest.of_content selected |> Content_digest.to_string)
                  ~display:selected identity content_identity
              else Invalid_selector "text range is outside the target observation"
          | Selector.Region_id local ->
              let observation =
                Observation_id.make
                  ("observation:" ^ Workspace_path.to_canonical_string path)
              in
              (match observation with
              | Error message -> Invalid_selector message
              | Ok observation ->
                  let id =
                    Region_id.make ~observation
                      ~local:(Identifier.to_string local)
                  in
                  (match id with
                  | Ok id -> (
                      match known_region regions id with
                      | None -> Not_found
                      | Some region ->
                          resolved ?region_fingerprint:(Region.fingerprint region)
                            ?display:(Region.summary region) identity
                            content_identity)
                  | Error message -> Invalid_selector message))
          | Selector.Row_filter filter ->
              if
                Reference.target_interpreter (Reference.target reference)
                <> Some "jsonl"
              then Invalid_selector "row-filter requires the jsonl interpreter"
              else
                (match Jsonl_interpreter.select filter content with
                | Error message -> Invalid_selector message
                | Ok Jsonl_interpreter.No_match -> Not_found
                | Ok Jsonl_interpreter.Ambiguous ->
                    Invalid_selector
                      "row-filter resolves to more than one JSONL row"
                | Ok (Jsonl_interpreter.One selected) ->
                    resolved
                      ~region_fingerprint:
                        (Content_digest.of_content selected.display
                        |> Content_digest.to_string)
                      ~display:selected.display identity content_identity)
          | Selector.Extension _ ->
              Invalid_selector
                "extension selector requires its declared interpreter")
