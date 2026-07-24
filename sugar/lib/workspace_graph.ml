type query_direction = Incoming | Outgoing | Both
type edge_direction = Incoming_edge | Outgoing_edge | Internal_edge
type edge_kind = Reference_occurrence | Semantic_relation

type resolution =
  | Resolved
  | Unresolved
  | Invalid_selector
  | Unreadable
  | Not_checked

type edge = {
  direction : edge_direction;
  kind : edge_kind;
  predicate : string;
  source : Region_address.t;
  target : Region_address.t;
  reference : Reference_id.t option;
  annotation : Annotation_id.t option;
  occurrence_range : Text_range.t option;
  source_resolution : resolution;
  target_resolution : resolution;
}

type coverage = {
  scanned_artifacts : int;
  interpreted_artifacts : int;
  unsupported_artifacts : int;
  failed_artifacts : int;
  complete : bool;
}

type t = {
  artifact : Workspace_path.t;
  query_direction : query_direction;
  predicate : string option;
  limit : int;
  matches : edge list;
  coverage : coverage;
  truncated : bool;
}

type error = Usage of string | Internal of string

let ( let* ) = Result.bind

type build_error = Query_error of error | Unstable_workspace

type snapshot = {
  artifacts : Artifact.t list;
  regions : Region.t list;
  references : Reference.t list;
  occurrences : Reference_occurrence.t list;
  relations : Relation.t list;
  coverage : coverage;
}

let artifact (value : t) = value.artifact
let query_direction (value : t) = value.query_direction
let predicate (value : t) = value.predicate
let limit (value : t) = value.limit
let matches (value : t) = value.matches
let coverage (value : t) = value.coverage
let truncated (value : t) = value.truncated
let direction (value : edge) = value.direction
let kind (value : edge) = value.kind
let edge_predicate (value : edge) = value.predicate
let source (value : edge) = value.source
let target (value : edge) = value.target
let reference (value : edge) = value.reference
let annotation (value : edge) = value.annotation
let occurrence_range (value : edge) = value.occurrence_range
let source_resolution (value : edge) = value.source_resolution
let target_resolution (value : edge) = value.target_resolution

let is_markdown_path path =
  match List.rev (Workspace_path.segments path) with
  | [] -> false
  | basename :: _ ->
      Filename.check_suffix basename ".md"
      || Filename.check_suffix basename ".markdown"

let workspace_path artifact =
  match Artifact.origin artifact with
  | Artifact.Workspace path -> Some path
  | Artifact.Git _ | Artifact.Web _ | Artifact.Generated _ | Artifact.External _ ->
      None

let find_artifact artifacts id =
  List.find_opt (fun artifact -> Artifact_id.equal id (Artifact.id artifact))
    artifacts

let artifact_exists artifacts origin =
  List.exists
    (fun artifact -> Artifact.compare_origin origin (Artifact.origin artifact) = 0)
    artifacts

let terminal_error result =
  match Command_result.termination result with
  | Command_result.Completed -> None
  | Command_result.Usage_failure message -> Some (Usage message)
  | Command_result.Internal_failure _ ->
      Some (Internal "workspace observation failed")

let same_artifact_observation left right =
  Artifact_id.equal (Artifact.id left) (Artifact.id right)
  && Artifact.compare_origin (Artifact.origin left) (Artifact.origin right) = 0
  && Content_identity.equal
       (Artifact.content_identity left)
       (Artifact.content_identity right)

let sort_artifacts artifacts =
  List.sort
    (fun left right -> Artifact_id.compare (Artifact.id left) (Artifact.id right))
    artifacts

let same_inventory left right =
  let left = sort_artifacts left in
  let right = sort_artifacts right in
  List.length left = List.length right
  && List.for_all2 same_artifact_observation left right

let observations_match_scan scanned observations =
  List.for_all
    (fun observed ->
      List.exists
        (fun scanned -> same_artifact_observation scanned observed)
        scanned)
    observations

let build_once ~workspace =
  let scan = Workspace_scan.scan ~workspace in
  match terminal_error scan with
  | Some error -> Error (Query_error error)
  | None ->
      let scanned = Command_result.artifacts scan in
      let rec observe artifacts regions references occurrences relations
          interpreted failed = function
        | [] ->
            let observed_ids = List.map Artifact.id artifacts in
            let unsupported =
              List.fold_left
                (fun count artifact ->
                  if
                    List.exists
                      (fun id -> Artifact_id.equal id (Artifact.id artifact))
                      observed_ids
                  then count
                  else count + 1)
                0 scanned
            in
            let failed =
              failed + List.length (Command_result.diagnostics scan)
            in
            let coverage =
              {
                scanned_artifacts = List.length scanned;
                interpreted_artifacts = interpreted;
                unsupported_artifacts = unsupported;
                failed_artifacts = failed;
                complete = unsupported = 0 && failed = 0;
              }
            in
            let final_scan = Workspace_scan.scan ~workspace in
            (match terminal_error final_scan with
            | Some error -> Error (Query_error error)
            | None ->
                if
                  not
                    (same_inventory scanned
                       (Command_result.artifacts final_scan))
                then Error Unstable_workspace
                else
                  Ok
                    {
                      artifacts = scanned;
                      regions = List.rev regions;
                      references = List.rev references;
                      occurrences = List.rev occurrences;
                      relations = List.rev relations;
                      coverage;
                    })
        | scanned_artifact :: rest -> (
            match workspace_path scanned_artifact with
            | Some path when is_markdown_path path ->
                let observation =
                  Workspace_inspect.inspect_observation ~workspace ~artifact:path
                in
                let result = observation.result in
                (match terminal_error result with
                | Some (Usage message) ->
                    Error
                      (Query_error
                         (Internal
                            ("workspace artifact could not be inspected: "
                           ^ message)))
                | Some (Internal message) ->
                    Error (Query_error (Internal message))
                | None ->
                    let result_artifacts = Command_result.artifacts result in
                    if not (observations_match_scan scanned result_artifacts)
                    then Error Unstable_workspace
                    else if Command_result.diagnostics result <> [] then
                      observe
                        (List.rev_append result_artifacts artifacts)
                        regions references occurrences relations interpreted
                        (failed + List.length result_artifacts)
                        rest
                    else
                      observe
                        (List.rev_append result_artifacts artifacts)
                        (List.rev_append (Command_result.regions result) regions)
                        (List.rev_append
                           (Command_result.references result)
                           references)
                        (List.rev_append observation.occurrences occurrences)
                        (List.rev_append observation.relations relations)
                        (interpreted + List.length result_artifacts)
                        failed rest)
            | Some _ | None ->
                observe artifacts regions references occurrences relations
                  interpreted failed rest)
      in
      observe [] [] [] [] [] 0 0 scanned

let build ~workspace =
  match build_once ~workspace with
  | Ok snapshot -> Ok snapshot
  | Error (Query_error error) -> Error error
  | Error Unstable_workspace -> (
      match build_once ~workspace with
      | Ok snapshot -> Ok snapshot
      | Error (Query_error error) -> Error error
      | Error Unstable_workspace ->
          Error (Internal "workspace changed during graph observation"))

let origin_of_artifact_id snapshot id =
  match find_artifact snapshot.artifacts id with
  | Some artifact -> Ok (Artifact.origin artifact)
  | None -> Error (Internal "graph endpoint artifact is not in the workspace")

let address_of_region_id snapshot id =
  match
    List.find_opt (fun region -> Region_id.equal id (Region.id region))
      snapshot.regions
  with
  | None -> Error (Internal "graph relation region is not in the observation")
  | Some region ->
      let* origin = origin_of_artifact_id snapshot (Region_id.artifact id) in
      Region_address.make ~artifact:origin
        ~selector:(Selector.Region_id (Region_id.local id))
        ~interpreter:(Region.interpreter region) ()
      |> Result.map_error (fun message -> Internal message)

let address_of_region_ref snapshot = function
  | Region_ref.Resolved id -> address_of_region_id snapshot id
  | Region_ref.Address address -> Ok address

let source_of_occurrence snapshot occurrence =
  match Reference_occurrence.source_region occurrence with
  | Some id -> address_of_region_id snapshot id
  | None ->
      let* origin =
        origin_of_artifact_id snapshot
          (Reference_occurrence.source_artifact occurrence)
      in
      Region_address.make ~artifact:origin ~selector:Selector.Whole_artifact ()
      |> Result.map_error (fun message -> Internal message)

let find_reference snapshot id =
  List.find_opt
    (fun reference -> Reference_id.equal id (Reference.id reference))
    snapshot.references

let reference_resolution ~workspace snapshot reference =
  match
    Reference_resolver.resolve ~workspace ~regions:snapshot.regions reference
  with
  | Reference_resolver.Resolved _ -> Resolved
  | Reference_resolver.Not_found -> Unresolved
  | Reference_resolver.Invalid_selector _ -> Invalid_selector
  | Reference_resolver.Read_failure -> Unreadable

let direct_resolution snapshot address =
  match Region_address.artifact address with
  | Artifact.Workspace path -> (
      let origin = Artifact.workspace path in
      match Region_address.selector address with
      | Selector.Whole_artifact ->
          if artifact_exists snapshot.artifacts origin then Resolved
          else Unresolved
      | Selector.Region_id local ->
          let artifact =
            Artifact_id.make
              ("artifact:" ^ Workspace_path.to_canonical_string path)
          in
          (match artifact with
          | Error _ -> Invalid_selector
          | Ok artifact ->
              if
                List.exists
                  (fun region ->
                    Artifact_id.equal artifact (Region.artifact region)
                    && Identifier.equal local
                         (Region.id region |> Region_id.local))
                  snapshot.regions
              then Resolved
              else Unresolved)
      | Selector.Text_range _ | Selector.Row_filter _ -> Not_checked)
  | Artifact.Git _ | Artifact.Web _ | Artifact.Generated _ | Artifact.External _ ->
      Not_checked

let target_of_occurrence ~workspace snapshot occurrence =
  match Reference_occurrence.target occurrence with
  | Reference_occurrence.Direct address ->
      Ok (address, None, direct_resolution snapshot address)
  | Reference_occurrence.Named id -> (
      match find_reference snapshot id with
      | None ->
          Error (Internal "named reference occurrence has no declaration")
      | Some reference ->
          Ok
            ( Reference.target reference,
              Some id,
              reference_resolution ~workspace snapshot reference ))

let endpoint_artifact address = Region_address.artifact address

let selected_origin artifact = Artifact.workspace artifact

let classify_direction selected source target =
  let source_matches =
    Artifact.compare_origin selected (endpoint_artifact source) = 0
  in
  let target_matches =
    Artifact.compare_origin selected (endpoint_artifact target) = 0
  in
  match (source_matches, target_matches) with
  | true, true -> Some Internal_edge
  | true, false -> Some Outgoing_edge
  | false, true -> Some Incoming_edge
  | false, false -> None

let include_direction query edge =
  match (query, edge) with
  | Both, _ -> true
  | Incoming, (Incoming_edge | Internal_edge) -> true
  | Outgoing, (Outgoing_edge | Internal_edge) -> true
  | Incoming, Outgoing_edge | Outgoing, Incoming_edge -> false

let annotation_id relation source =
  match Region_address.artifact source with
  | Artifact.Workspace path ->
      let* artifact =
        Artifact_id.make
          ("artifact:" ^ Workspace_path.to_canonical_string path)
      in
      Annotation_id.make ~artifact
        ~local:(Relation.id relation |> Identifier.to_string)
  | Artifact.Git _ | Artifact.Web _ | Artifact.Generated _ | Artifact.External _ ->
      Error "relation source is not a workspace artifact"

let edge_of_occurrence ~workspace snapshot selected occurrence =
  let* source = source_of_occurrence snapshot occurrence in
  let* target, reference, resolution =
    target_of_occurrence ~workspace snapshot occurrence
  in
  match classify_direction selected source target with
  | None -> Ok None
  | Some direction ->
      Ok
        (Some
           {
             direction;
             kind = Reference_occurrence;
             predicate = "references";
             source;
             target;
             reference;
             annotation = None;
             occurrence_range =
               Some (Reference_occurrence.range occurrence);
             source_resolution = direct_resolution snapshot source;
             target_resolution = resolution;
           })

let target_of_relation ~workspace snapshot relation =
  match Relation.object_ relation with
  | Relation.Region region ->
      let* address = address_of_region_ref snapshot region in
      Ok (address, None, direct_resolution snapshot address)
  | Relation.Reference id -> (
      match find_reference snapshot id with
      | None -> Error (Internal "relation refers to an unknown reference")
      | Some reference ->
          Ok
            ( Reference.target reference,
              Some id,
              reference_resolution ~workspace snapshot reference ))

let edge_of_relation ~workspace snapshot selected relation =
  match Relation.subject relation with
  | Relation.Reference _ ->
      Error (Internal "standard annotation relation has a reference subject")
  | Relation.Region subject ->
      let* source = address_of_region_ref snapshot subject in
      let* target, reference, resolution =
        target_of_relation ~workspace snapshot relation
      in
      (match classify_direction selected source target with
      | None -> Ok None
      | Some direction ->
          let* annotation =
            annotation_id relation source
            |> Result.map_error (fun message -> Internal message)
          in
          Ok
            (Some
               {
                 direction;
                 kind = Semantic_relation;
                 predicate = Relation.predicate relation;
                 source;
                 target;
                 reference;
                 annotation = Some annotation;
                 occurrence_range = None;
                 source_resolution = direct_resolution snapshot source;
                 target_resolution = resolution;
               }))

let direction_rank = function
  | Outgoing_edge -> 0
  | Incoming_edge -> 1
  | Internal_edge -> 2

let kind_rank = function Reference_occurrence -> 0 | Semantic_relation -> 1

let compare_optional compare left right = Option.compare compare left right

let compare_edge left right =
  match Int.compare (direction_rank left.direction) (direction_rank right.direction) with
  | 0 -> (
      match String.compare left.predicate right.predicate with
      | 0 -> (
          match Region_address.compare left.source right.source with
          | 0 -> (
              match Region_address.compare left.target right.target with
              | 0 -> (
                  match Int.compare (kind_rank left.kind) (kind_rank right.kind) with
                  | 0 -> (
                      match
                        compare_optional Reference_id.compare left.reference
                          right.reference
                      with
                      | 0 ->
                          compare_optional Annotation_id.compare left.annotation
                            right.annotation
                      | other -> other)
                  | other -> other)
              | other -> other)
          | other -> other)
      | other -> other)
  | other -> other

let rec take count values =
  if count = 0 then []
  else
    match values with
    | [] -> []
    | value :: rest -> value :: take (count - 1) rest

let query ~workspace ~artifact ~direction ~predicate ~limit =
  if limit <= 0 then Error (Usage "--limit must be a positive integer")
  else
    let* snapshot = build ~workspace in
    let selected = selected_origin artifact in
    if not (artifact_exists snapshot.artifacts selected) then
      Error (Usage "artifact does not exist")
    else
      let* occurrences =
        List.fold_left
          (fun result occurrence ->
            let* edges = result in
            let* edge =
              edge_of_occurrence ~workspace snapshot selected occurrence
            in
            Ok (match edge with None -> edges | Some edge -> edge :: edges))
          (Ok []) snapshot.occurrences
      in
      let* relations =
        List.fold_left
          (fun result relation ->
            let* edges = result in
            let* edge = edge_of_relation ~workspace snapshot selected relation in
            Ok (match edge with None -> edges | Some edge -> edge :: edges))
          (Ok []) snapshot.relations
      in
      let all =
        List.rev_append occurrences relations
        |> List.filter (fun edge -> include_direction direction edge.direction)
        |> List.filter (fun edge ->
               match predicate with
               | None -> true
               | Some predicate ->
                   String.equal predicate (edge : edge).predicate)
        |> List.sort compare_edge
      in
      let truncated = List.length all > limit in
      Ok
        {
          artifact;
          query_direction = direction;
          predicate;
          limit;
          matches = take limit all;
          coverage = snapshot.coverage;
          truncated;
        }
