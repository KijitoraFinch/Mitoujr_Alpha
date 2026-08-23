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
  scanned_observations : int;
  interpreted_observations : int;
  unsupported_observations : int;
  failed_observations : int;
  complete : bool;
}

type t = {
  observation : Workspace_path.t;
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
  observations : Observation.t list;
  regions : Region.t list;
  references : Reference.t list;
  occurrences : Reference_occurrence.t list;
  relations : Relation.t list;
  coverage : coverage;
}

type extension_dispatch = {
  manifest : Extension_manifest.t;
  session : Extension_runtime.session;
}

type selected_interpreter = Built_in_markdown | Selected_extension

let observation (value : t) = value.observation
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

let is_markdown_observation observation =
  let observation_type = Observation.observation_type observation in
  String.equal (Observation_type.name observation_type) "text/markdown"
  && String.equal (Observation_type.version observation_type) "1"

let workspace_path observation =
  match Observation.origin observation with
  | Origin.Workspace path -> Some path
  | Origin.Git _
  | Origin.Web _
  | Origin.Generated _
  | Origin.External _
  | Origin.Extension _ ->
      None

let find_observation observations id =
  List.find_opt (fun observation -> Observation_id.equal id (Observation.id observation))
    observations

let observation_exists observations origin =
  List.exists
    (fun observation -> Observation.compare_origin origin (Observation.origin observation) = 0)
    observations

let terminal_error result =
  match Command_result.termination result with
  | Command_result.Completed -> None
  | Command_result.Usage_failure message -> Some (Usage message)
  | Command_result.Internal_failure _ ->
      Some (Internal "workspace observation failed")

let same_observation left right =
  Observation_id.equal (Observation.id left) (Observation.id right)
  && Observation.compare_origin (Observation.origin left) (Observation.origin right) = 0
  && Observation_identity.equal
       (Observation.identity left)
       (Observation.identity right)
  && Option.equal Content_identity.equal
       (Observation.content_identity left)
       (Observation.content_identity right)

let sort_observations observations =
  List.sort
    (fun left right -> Observation_id.compare (Observation.id left) (Observation.id right))
    observations

let same_inventory left right =
  let left = sort_observations left in
  let right = sort_observations right in
  List.length left = List.length right
  && List.for_all2 same_observation left right

let observations_match_scan scanned observations =
  List.for_all
    (fun observed ->
      List.exists
        (fun scanned -> same_observation scanned observed)
        scanned)
    observations

let select_interpreter extension observation =
  let built_in = is_markdown_observation observation in
  match extension with
  | None -> Ok (if built_in then Some Built_in_markdown else None)
  | Some dispatch -> (
      let capability = Extension_manifest.capability dispatch.manifest in
      match Extension_applicability.accepts capability ~observation with
      | Error message ->
          Error
            (Query_error
               (Usage ("invalid extension applicability: " ^ message)))
      | Ok false ->
          Ok (if built_in then Some Built_in_markdown else None)
      | Ok true when built_in ->
          let observation_name =
            match workspace_path observation with
            | Some path -> Workspace_path.to_canonical_string path
            | None -> Observation_id.to_string (Observation.id observation)
          in
          Error
            (Query_error
               (Usage
                  (Printf.sprintf
                     "multiple interpreters apply to observation %s: markdown@1 and %s@%s"
                     observation_name
                     (Capability.name capability)
                     (Capability.version capability))))
      | Ok true -> Ok (Some Selected_extension))

let existing_inspection = function
  | Ok inspection -> Ok inspection
  | Error Workspace_inspect.Observation_changed -> Error Unstable_workspace
  | Error (Workspace_inspect.Invalid_observation message) ->
      Error (Query_error (Internal message))

let inspect_selected ~workspace ~observation extension = function
  | Built_in_markdown ->
      Workspace_inspect.inspect_existing_observation ~workspace ~observation
      |> existing_inspection
  | Selected_extension -> (
      match extension with
      | None ->
          Error
            (Query_error
               (Internal "selected extension has no checked runtime session"))
      | Some dispatch ->
          Workspace_inspect.inspect_existing_observation_with_extension_session
            ~workspace ~observation ~manifest:dispatch.manifest
            ~session:dispatch.session
          |> existing_inspection)

let classify_for_extension extension path =
  match extension with
  | None -> Ok (Workspace_observation_type.classify path)
  | Some dispatch ->
      let capability = Extension_manifest.capability dispatch.manifest in
      let* association = Extension_applicability.associate capability ~path in
      (match association with
      | Extension_applicability.Associated observation_type ->
          Ok observation_type
      | Extension_applicability.Not_associated ->
          Ok (Workspace_observation_type.classify path))

let scan_workspace ~extension ~workspace =
  Workspace_scan.scan_with_classifier ~workspace
    ~classify:(classify_for_extension extension)

let build_once ~extension ~workspace =
  let scan = scan_workspace ~extension ~workspace in
  match terminal_error scan with
  | Some error -> Error (Query_error error)
  | None ->
      let scanned = Command_result.observations scan |> sort_observations in
      let rec interpret observations regions references occurrences relations
          interpreted failed = function
        | [] ->
            let observed_ids = List.map Observation.id observations in
            let unsupported =
              List.fold_left
                (fun count observation ->
                  if
                    List.exists
                      (fun id -> Observation_id.equal id (Observation.id observation))
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
                scanned_observations = List.length scanned;
                interpreted_observations = interpreted;
                unsupported_observations = unsupported;
                failed_observations = failed;
                complete = unsupported = 0 && failed = 0;
              }
            in
            let final_scan = scan_workspace ~extension ~workspace in
            (match terminal_error final_scan with
            | Some error -> Error (Query_error error)
            | None ->
                if
                  not
                    (same_inventory scanned
                       (Command_result.observations final_scan))
                then Error Unstable_workspace
                else
                  Ok
                    {
                      observations = scanned;
                      regions = List.rev regions;
                      references = List.rev references;
                      occurrences = List.rev occurrences;
                      relations = List.rev relations;
                      coverage;
                    })
        | scanned_observation :: rest -> (
            match workspace_path scanned_observation with
            | Some _ -> (
                let* selected = select_interpreter extension scanned_observation in
                match selected with
                | None ->
                    interpret observations regions references occurrences relations
                      interpreted failed rest
                | Some selected ->
                    let* inspection =
                      inspect_selected ~workspace
                        ~observation:scanned_observation extension selected
                    in
                    let result = inspection.result in
                    (match terminal_error result with
                    | Some (Usage message) ->
                        Error
                          (Query_error
                             (Internal
                                ("workspace observation could not be inspected: "
                               ^ message)))
                    | Some (Internal message) ->
                        Error (Query_error (Internal message))
                    | None ->
                        let result_observations =
                          Command_result.observations result
                        in
                        if
                          not
                            (observations_match_scan scanned result_observations)
                        then Error Unstable_workspace
                        else if Command_result.diagnostics result <> [] then
                          interpret
                            (List.rev_append result_observations observations)
                            regions references occurrences relations interpreted
                            (failed + List.length result_observations)
                            rest
                        else
                          interpret
                            (List.rev_append result_observations observations)
                            (List.rev_append
                               (Command_result.regions result)
                               regions)
                            (List.rev_append
                               (Command_result.references result)
                               references)
                            (List.rev_append inspection.occurrences occurrences)
                            (List.rev_append inspection.relations relations)
                            (interpreted + List.length result_observations)
                            failed rest))
            | None ->
                interpret observations regions references occurrences relations
                  interpreted failed rest)
      in
      interpret [] [] [] [] [] 0 0 scanned

let build ~workspace =
  match build_once ~extension:None ~workspace with
  | Ok snapshot -> Ok snapshot
  | Error (Query_error error) -> Error error
  | Error Unstable_workspace -> (
      match build_once ~extension:None ~workspace with
      | Ok snapshot -> Ok snapshot
      | Error (Query_error error) -> Error error
      | Error Unstable_workspace ->
          Error (Internal "workspace changed during graph observation"))

let extension_build_attempt ~workspace ~manifest ~executable ~arguments =
  match
    Extension_runtime.with_checked_session ~executable ~arguments
      ~limits:Extension_runtime.default_limits ~manifest (fun session ->
        Ok
          (build_once ~workspace
             ~extension:(Some { manifest; session })))
  with
  | Ok result -> result
  | Error failure ->
      Error
        (Query_error
           (Internal
              (Printf.sprintf "extension runtime %s: %s"
                 (Extension_runtime.failure_code failure)
                 (Extension_runtime.failure_message failure))))

let build_with_extension ~workspace ~manifest ~executable ~arguments =
  match extension_build_attempt ~workspace ~manifest ~executable ~arguments with
  | Ok snapshot -> Ok snapshot
  | Error (Query_error error) -> Error error
  | Error Unstable_workspace -> (
      match
        extension_build_attempt ~workspace ~manifest ~executable ~arguments
      with
      | Ok snapshot -> Ok snapshot
      | Error (Query_error error) -> Error error
      | Error Unstable_workspace ->
          Error (Internal "workspace changed during graph observation"))

let origin_of_observation_id snapshot id =
  match find_observation snapshot.observations id with
  | Some observation -> Ok (Observation.origin observation)
  | None -> Error (Internal "graph endpoint observation is not in the workspace")

let address_of_region_id snapshot id =
  match
    List.find_opt (fun region -> Region_id.equal id (Region.id region))
      snapshot.regions
  with
  | None -> Error (Internal "graph relation region is not in the observation")
  | Some region ->
      let* origin = origin_of_observation_id snapshot (Region_id.observation id) in
      let selector = Selector.Region_id (Region_id.local id) in
      (match Region.interpreter_identity region with
      | None -> Region_address.make ~origin ~selector ()
      | Some interpreter ->
          Region_address.make ~origin ~selector
            ~interpreter:(Interpreter.name interpreter)
            ~interpreter_version:(Interpreter.version interpreter) ())
      |> Result.map_error (fun message -> Internal message)

let address_of_region_ref snapshot = function
  | Region_ref.Resolved id -> address_of_region_id snapshot id
  | Region_ref.Address address -> Ok address

let source_of_occurrence snapshot occurrence =
  match Reference_occurrence.source_region occurrence with
  | Some id -> address_of_region_id snapshot id
  | None ->
      let* origin =
        origin_of_observation_id snapshot
          (Reference_occurrence.source_observation occurrence)
      in
      Region_address.make ~origin:origin ~selector:Selector.Whole_observation ()
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
  match Region_address.origin address with
  | Origin.Workspace path -> (
      let origin = Observation.workspace path in
      match Region_address.selector address with
      | Selector.Whole_observation ->
          if observation_exists snapshot.observations origin then Resolved
          else Unresolved
      | Selector.Region_id local ->
          let observation =
            Observation_id.make
              ("observation:" ^ Workspace_path.to_canonical_string path)
          in
          (match observation with
          | Error _ -> Invalid_selector
          | Ok observation ->
              if
                List.exists
                  (fun region ->
                    Observation_id.equal observation (Region.observation region)
                    && Identifier.equal local
                         (Region.id region |> Region_id.local))
                  snapshot.regions
              then Resolved
              else Unresolved)
      | Selector.Text_range _
      | Selector.Row_filter _
      | Selector.Extension _ ->
          Not_checked)
  | Origin.Git _
  | Origin.Web _
  | Origin.Generated _
  | Origin.External _
  | Origin.Extension _ ->
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

let endpoint_origin address = Region_address.origin address

let selected_origin observation = Observation.workspace observation

let classify_direction selected source target =
  let source_matches =
    Observation.compare_origin selected (endpoint_origin source) = 0
  in
  let target_matches =
    Observation.compare_origin selected (endpoint_origin target) = 0
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
  match Region_address.origin source with
  | Origin.Workspace path ->
      let* observation =
        Observation_id.make
          ("observation:" ^ Workspace_path.to_canonical_string path)
      in
      Annotation_id.make ~observation
        ~local:(Relation.id relation |> Identifier.to_string)
  | Origin.Git _
  | Origin.Web _
  | Origin.Generated _
  | Origin.External _
  | Origin.Extension _ ->
      Error "relation source is not a workspace observation"

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

let query_snapshot ~workspace ~observation ~direction ~predicate ~limit snapshot =
  let selected = selected_origin observation in
  if not (observation_exists snapshot.observations selected) then
    Error (Usage "observation does not exist")
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
             | Some predicate -> String.equal predicate (edge : edge).predicate)
      |> List.sort compare_edge
    in
    let truncated = List.length all > limit in
    Ok
      {
        observation;
        query_direction = direction;
        predicate;
        limit;
        matches = take limit all;
        coverage = snapshot.coverage;
        truncated;
      }

let query ~workspace ~observation ~direction ~predicate ~limit =
  if limit <= 0 then Error (Usage "--limit must be a positive integer")
  else
    let* snapshot = build ~workspace in
    query_snapshot ~workspace ~observation ~direction ~predicate ~limit snapshot

let query_with_extension ~workspace ~observation ~direction ~predicate ~limit
    ~manifest ~executable ~arguments =
  if limit <= 0 then Error (Usage "--limit must be a positive integer")
  else
    let capability = Extension_manifest.capability manifest in
    if Capability.kind capability <> Capability.Interpreter then
      Error (Usage "extension related requires an interpreter capability")
    else
      match Extension_applicability.validate capability with
      | Error message -> Error (Usage ("invalid extension applicability: " ^ message))
      | Ok () ->
          let* snapshot =
            build_with_extension ~workspace ~manifest ~executable ~arguments
          in
          query_snapshot ~workspace ~observation ~direction ~predicate ~limit
            snapshot
