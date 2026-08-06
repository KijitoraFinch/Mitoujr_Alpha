let binding = function
  | Reference.Pinned -> "pinned"
  | Reference.Tracking -> "tracking"
  | Reference.Floating -> "floating"

let selected_artifact path artifacts =
  List.find_opt
    (fun artifact ->
      match Artifact.origin artifact with
      | Origin.Workspace candidate -> Workspace_path.equal path candidate
      | Origin.Git _
      | Origin.Web _
      | Origin.Generated _
      | Origin.External _
      | Origin.Extension _ ->
          false)
    artifacts

let render_regions buffer regions =
  let regions =
    List.sort
      (fun left right -> Region_id.compare (Region.id left) (Region.id right))
      regions
  in
  match regions with
  | [] -> ()
  | _ ->
      Buffer.add_string buffer "\n## Regions\n";
      List.iter
        (fun region ->
          let local = Region.id region |> Region_id.local |> Identifier.to_string in
          let location =
            match Region.range region with
            | None -> ""
            | Some range ->
                Printf.sprintf " [bytes %d:%d]" (Text_range.start range)
                  (Text_range.end_ range)
          in
          Buffer.add_string buffer ("- " ^ local ^ location ^ "\n");
          match Region.summary region with
          | None -> ()
          | Some summary -> Buffer.add_string buffer ("  " ^ summary ^ "\n"))
        regions

let render_references buffer references =
  let references =
    List.sort
      (fun left right ->
        Reference_id.compare (Reference.id left) (Reference.id right))
      references
  in
  match references with
  | [] -> ()
  | _ ->
      Buffer.add_string buffer "\n## References\n";
      List.iter
        (fun reference ->
          let local =
            Reference.id reference |> Reference_id.local
            |> Identifier.to_string
          in
          Buffer.add_string buffer
            (Printf.sprintf "- %s [%s] -> %s\n" local
               (binding (Reference.binding reference))
               (Agent_format.address (Reference.target reference))))
        references

let annotation_object artifacts = function
  | Annotation.Reference_object id ->
      Printf.sprintf "reference:%s#%s"
        (Reference_id.artifact id |> Artifact_id.to_string)
        (Reference_id.local id |> Identifier.to_string)
  | Annotation.Region_object region ->
      Agent_format.region_ref ~artifacts region
  | Annotation.Literal value -> Printf.sprintf "%S" value

let render_annotations buffer artifacts annotations =
  let annotations =
    List.sort
      (fun left right ->
        Annotation_id.compare (Annotation.id left) (Annotation.id right))
      annotations
  in
  match annotations with
  | [] -> ()
  | _ ->
      Buffer.add_string buffer "\n## Annotations\n";
      List.iter
        (fun annotation ->
          let local =
            Annotation.id annotation |> Annotation_id.local
            |> Identifier.to_string
          in
          let subject =
            match Annotation.subject annotation with
            | Annotation.Region region ->
                Agent_format.region_ref ~artifacts region
          in
          Buffer.add_string buffer
            (Printf.sprintf "- %s: %s --%s--> %s\n" local subject
               (Annotation.predicate annotation)
               (annotation_object artifacts (Annotation.object_ annotation))))
        annotations

let to_string ~artifact observation =
  let result = observation.Workspace_inspect.result in
  let artifacts = Command_result.artifacts result in
  let buffer = Buffer.create 1024 in
  Buffer.add_string buffer
    ("# " ^ Workspace_path.to_canonical_string artifact ^ "\n");
  (match selected_artifact artifact artifacts with
  | None -> ()
  | Some descriptor ->
      let identity = Artifact.content_identity descriptor in
      Option.iter
        (fun media_type ->
          Buffer.add_string buffer ("mediaType: " ^ media_type ^ "\n"))
        (Artifact.media_type descriptor);
      Buffer.add_string buffer
        (Printf.sprintf "contentIdentity: %s (%d bytes)\n"
           (Content_identity.display_hash identity)
           (Content_identity.byte_length identity)));
  render_regions buffer (Command_result.regions result);
  render_references buffer (Command_result.references result);
  render_annotations buffer artifacts (Command_result.annotations result);
  Buffer.add_string buffer "\n## Content\n\n";
  (match observation.content with
  | None -> ()
  | Some content -> Buffer.add_string buffer content);
  if
    match observation.content with
    | Some content -> String.length content = 0 || content.[String.length content - 1] <> '\n'
    | None -> true
  then Buffer.add_char buffer '\n';
  Buffer.contents buffer
