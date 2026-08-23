let binding = function
  | Reference.Pinned -> "pinned"
  | Reference.Tracking -> "tracking"
  | Reference.Floating -> "floating"

let selected_observation path observations =
  List.find_opt
    (fun observation ->
      match Observation.origin observation with
      | Origin.Workspace candidate -> Workspace_path.equal path candidate
      | Origin.Git _
      | Origin.Web _
      | Origin.Generated _
      | Origin.External _
      | Origin.Extension _ ->
          false)
    observations

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

let annotation_object observations = function
  | Annotation.Reference_object id ->
      Printf.sprintf "reference:%s#%s"
        (Reference_id.observation id |> Observation_id.to_string)
        (Reference_id.local id |> Identifier.to_string)
  | Annotation.Region_object region ->
      Agent_format.region_ref ~observations region
  | Annotation.Literal value -> Printf.sprintf "%S" value

let render_annotations buffer observations annotations =
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
                Agent_format.region_ref ~observations region
          in
          Buffer.add_string buffer
            (Printf.sprintf "- %s: %s --%s--> %s\n" local subject
               (Annotation.predicate annotation)
               (annotation_object observations (Annotation.object_ annotation))))
        annotations

let to_string ~path snapshot =
  let result = snapshot.Workspace_inspect.result in
  let observations = Command_result.observations result in
  let buffer = Buffer.create 1024 in
  Buffer.add_string buffer
    ("# " ^ Workspace_path.to_canonical_string path ^ "\n");
  (match selected_observation path observations with
  | None -> ()
  | Some observed ->
      let identity = Observation.identity observed in
      let observation_type =
        Observation_identity.observation_type identity
      in
      Buffer.add_string buffer
        (Printf.sprintf "observationType: %s@%s\nobservationIdentity: %s\n"
           (Observation_type.name observation_type)
           (Observation_type.version observation_type)
           (Observation_identity.key identity));
      Option.iter
        (fun content_identity ->
          Buffer.add_string buffer
            (Printf.sprintf "contentIdentity: %s (%d bytes)\n"
               (Content_identity.display_hash content_identity)
               (Content_identity.byte_length content_identity)))
        (Observation.content_identity observed));
  render_regions buffer (Command_result.regions result);
  render_references buffer (Command_result.references result);
  render_annotations buffer observations (Command_result.annotations result);
  Buffer.add_string buffer "\n## Content\n\n";
  (match snapshot.content with
  | None -> ()
  | Some content -> Buffer.add_string buffer content);
  if
    match snapshot.content with
    | Some content -> String.length content = 0 || content.[String.length content - 1] <> '\n'
    | None -> true
  then Buffer.add_char buffer '\n';
  Buffer.contents buffer
