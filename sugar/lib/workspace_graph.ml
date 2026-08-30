type query_direction = Incoming | Outgoing | Both
type region_scope = Exact | Contained
type edge_direction = Incoming_edge | Outgoing_edge | Internal_edge
type edge_kind = Reference_occurrence | Semantic_relation
type result_status = Complete | Incomplete | Failed

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
  query_region : Identifier.t option;
  region_scope : region_scope option;
  query_direction : query_direction;
  predicate : string option;
  limit : int;
  matches : edge list;
  diagnostics : Diagnostic.t list;
  result_status : result_status;
  coverage : coverage;
  truncated : bool;
}

type error = Usage of string | Internal of string

let ( let* ) = Result.bind

type build_error =
  | Query_error of error
  | Diagnostic_error of Diagnostic.t
  | Unstable_workspace

type snapshot = {
  observations : Observation.t list;
  regions : Region.t list;
  references : Reference.t list;
  occurrences : Reference_occurrence.t list;
  relations : Relation.t list;
  diagnostics : Diagnostic.t list;
  coverage : coverage;
}

let observation (value : t) = value.observation
let query_region (value : t) = value.query_region
let region_scope (value : t) = value.region_scope
let query_direction (value : t) = value.query_direction
let predicate (value : t) = value.predicate
let limit (value : t) = value.limit
let matches (value : t) = value.matches
let diagnostics (value : t) = value.diagnostics
let result_status (value : t) = value.result_status
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

let select_interpreter registry observation =
  Interpreter_dispatcher.select registry observation
  |> Result.map_error (fun message -> Query_error (Usage message))

let existing_inspection = function
  | Ok inspection -> Ok inspection
  | Error Workspace_inspect.Observation_changed -> Error Unstable_workspace
  | Error (Workspace_inspect.Invalid_observation message) ->
      Error (Query_error (Internal message))

let inspect_selected ~registry ~workspace ~observation = function
  | Interpreter_dispatcher.Built_in_markdown ->
      Workspace_inspect.inspect_existing_observation ~workspace ~observation
      |> existing_inspection
  | Interpreter_dispatcher.Installed _ ->
      let* inspection =
        Workspace_inspect.inspect_existing_observation_with_registry ~workspace
          ~observation ~registry
        |> existing_inspection
      in
      (match
         List.find_opt
           (fun diagnostic ->
             match Diagnostic.extension_failure diagnostic with
             | Some failure ->
                 Extension_failure.operation failure = Extension_failure.Session
             | None -> false)
           (Command_result.diagnostics inspection.result)
       with
      | Some diagnostic -> Error (Diagnostic_error diagnostic)
      | None -> Ok inspection)
  | Interpreter_dispatcher.Built_in_jsonl
  | Interpreter_dispatcher.Built_in_sidecar_v1 ->
      Error
        (Query_error
           (Internal
              "selected built-in interpreter cannot construct a workspace graph"))

let scan_workspace ~registry ~workspace =
  Workspace_scan.scan_with_classifier ~workspace
    ~classify:(Interpreter_dispatcher.classify_path registry)

let build_once ~registry ~workspace =
  let scan = scan_workspace ~registry ~workspace in
  match terminal_error scan with
  | Some error -> Error (Query_error error)
  | None ->
      let scanned = Command_result.observations scan |> sort_observations in
      let rec interpret observations regions references occurrences relations
          diagnostics interpreted failed = function
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
            let final_scan = scan_workspace ~registry ~workspace in
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
                      diagnostics =
                        List.rev_append (Command_result.diagnostics scan)
                          diagnostics
                        |> List.sort Diagnostic.compare;
                      coverage;
                    })
        | scanned_observation :: rest -> (
            match workspace_path scanned_observation with
            | Some _ -> (
                let* selected = select_interpreter registry scanned_observation in
                match selected with
                | None ->
                    interpret observations regions references occurrences relations
                      diagnostics interpreted failed rest
                | Some selected ->
                    let* inspection =
                      inspect_selected ~registry ~workspace
                        ~observation:scanned_observation selected
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
                            regions references occurrences relations
                            (List.rev_append
                               (Command_result.diagnostics result)
                               diagnostics)
                            interpreted
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
                            diagnostics
                            (interpreted + List.length result_observations)
                            failed rest))
            | None ->
                interpret observations regions references occurrences relations
                  diagnostics interpreted failed rest)
      in
      interpret [] [] [] [] [] [] 0 0 scanned

let build ~workspace =
  match build_once ~registry:Registry_snapshot.empty ~workspace with
  | Ok snapshot -> Ok snapshot
  | Error (Query_error _ as error) -> Error error
  | Error (Diagnostic_error _ as error) -> Error error
  | Error Unstable_workspace -> (
      match build_once ~registry:Registry_snapshot.empty ~workspace with
      | Ok snapshot -> Ok snapshot
      | Error (Query_error _ as error) -> Error error
      | Error (Diagnostic_error _ as error) -> Error error
      | Error Unstable_workspace ->
          Error
            (Query_error
               (Internal "workspace changed during graph observation")))

let build_with_registry ~workspace ~registry =
  match build_once ~registry ~workspace with
  | Ok snapshot -> Ok snapshot
  | Error (Query_error _ as error) -> Error error
  | Error (Diagnostic_error _ as error) -> Error error
  | Error Unstable_workspace -> (
      match
        build_once ~registry ~workspace
      with
      | Ok snapshot -> Ok snapshot
      | Error (Query_error _ as error) -> Error error
      | Error (Diagnostic_error _ as error) -> Error error
      | Error Unstable_workspace ->
          Error
            (Query_error
               (Internal "workspace changed during graph observation")))

let build_with_extension ~workspace ~manifest ~executable ~arguments =
  let* extension =
    Installed_extension.make ~manifest ~executable ~arguments
    |> Result.map_error (fun message -> Query_error (Usage message))
  in
  let* registry =
    Registry_snapshot.make [ extension ]
    |> Result.map_error (fun message -> Query_error (Usage message))
  in
  build_with_registry ~workspace ~registry

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
  let target = Reference.target reference in
  match
    (Region_address.origin target, Region_address.selector target)
  with
  | Origin.Workspace path, Selector.Extension selector -> (
      match
        Observation_id.make
          ("observation:" ^ Workspace_path.to_canonical_string path)
      with
      | Error _ -> Invalid_selector
      | Ok observation ->
          if
            List.exists
              (fun region ->
                Observation_id.equal observation (Region.observation region)
                && Selector.compare (Region.selector region)
                     (Selector.Extension selector)
                   = 0
                && Option.equal Interpreter.equal
                     (Region.interpreter_identity region)
                     (Region_address.interpreter_identity target))
              snapshot.regions
          then Resolved
          else Unresolved)
  | _ -> (
      match
        Reference_resolver.resolve ~workspace ~regions:snapshot.regions reference
      with
      | Reference_resolver.Resolved _ -> Resolved
      | Reference_resolver.Not_found -> Unresolved
      | Reference_resolver.Invalid_selector _ -> Invalid_selector
      | Reference_resolver.Read_failure -> Unreadable)

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
                         (Region.id region |> Region_id.local)
                    && Option.equal Interpreter.equal
                         (Region.interpreter_identity region)
                         (Region_address.interpreter_identity address))
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

type query_selection =
  | Selected_observation of Origin.t
  | Selected_region of {
      observation : Observation.t;
      region : Region.t;
      content : string;
      scope : region_scope;
      registry : Registry_snapshot.t;
    }

let find_observation_by_origin snapshot origin =
  List.find_opt
    (fun observation ->
      Observation.compare_origin origin (Observation.origin observation) = 0)
    snapshot.observations

let address_accepts_region_interpreter address region =
  match Region_address.interpreter_identity address with
  | None -> true
  | Some expected -> (
      match Region.interpreter_identity region with
      | Some actual -> Interpreter.equal expected actual
      | None -> false)

let select_unique_region ~missing ~ambiguous regions =
  match regions with
  | [ region ] -> Ok region
  | [] -> Error (Internal missing)
  | _ -> Error (Internal ambiguous)

let region_of_address snapshot observation address =
  match Region_address.selector address with
  | Selector.Whole_observation ->
      let id =
        Region_id.make ~observation:(Observation.id observation)
          ~local:"whole-observation"
      in
      Result.map
        (fun id ->
          Region.whole ~id
            ~observation_identity:(Observation.identity observation))
        id
      |> Result.map_error (fun message -> Internal message)
  | Selector.Region_id local -> (
      snapshot.regions
      |> List.filter (fun region ->
             Observation_id.equal (Region.observation region)
               (Observation.id observation)
             && Identifier.equal (Region.id region |> Region_id.local) local
             && address_accepts_region_interpreter address region)
      |> select_unique_region
           ~missing:"region endpoint is not present in the graph"
           ~ambiguous:
             "region endpoint is ambiguous without an interpreter identity")
  | selector -> (
      snapshot.regions
      |> List.filter (fun region ->
             Observation_id.equal (Region.observation region)
               (Observation.id observation)
             && Selector.compare (Region.selector region) selector = 0
             && address_accepts_region_interpreter address region)
      |> select_unique_region
           ~missing:
             "addressed region endpoint is not present in the interpreted graph"
           ~ambiguous:
             "addressed region endpoint is ambiguous without an interpreter identity")

let endpoint_matches snapshot selection address =
  match selection with
  | Selected_observation selected ->
      Ok (Observation.compare_origin selected (endpoint_origin address) = 0)
  | Selected_region selected ->
      if
        Observation.compare_origin (Observation.origin selected.observation)
          (endpoint_origin address)
        <> 0
      then Ok false
      else
        let* endpoint =
          region_of_address snapshot selected.observation address
        in
        (match
           Region_extent_dispatcher.classify ~registry:selected.registry
             ~observation:selected.observation ~content:selected.content
             ~left:selected.region ~right:endpoint
         with
        | Error failure ->
            Error
              (Internal
                 (Printf.sprintf "region relation failed [%s]: %s"
                    (Extension_failure.code failure)
                    (Extension_failure.message failure)))
        | Ok relation ->
            Ok
              (match selected.scope, relation with
              | Exact, Region_extent_relation.Equal -> true
              | Contained,
                (Region_extent_relation.Equal | Region_extent_relation.Contains)
                ->
                  true
              | Exact, _ | Contained, _ -> false))

let classify_direction snapshot selection source target =
  let* source_matches = endpoint_matches snapshot selection source in
  let* target_matches = endpoint_matches snapshot selection target in
  match (source_matches, target_matches) with
  | true, true -> Ok (Some Internal_edge)
  | true, false -> Ok (Some Outgoing_edge)
  | false, true -> Ok (Some Incoming_edge)
  | false, false -> Ok None

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

let edge_of_occurrence ~workspace snapshot selection occurrence =
  let* source = source_of_occurrence snapshot occurrence in
  let* target, reference, resolution =
    target_of_occurrence ~workspace snapshot occurrence
  in
  let* direction = classify_direction snapshot selection source target in
  match direction with
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

let edge_of_relation ~workspace snapshot selection relation =
  match Relation.subject relation with
  | Relation.Reference _ ->
      Error (Internal "standard annotation relation has a reference subject")
  | Relation.Region subject ->
      let* source = address_of_region_ref snapshot subject in
      let* target, reference, resolution =
        target_of_relation ~workspace snapshot relation
      in
      let* direction = classify_direction snapshot selection source target in
      (match direction with
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

let make_query_selection ~workspace ~observation ~region ~scope ~registry
    snapshot =
  let selected_origin = Observation.workspace observation in
  match find_observation_by_origin snapshot selected_origin with
  | None -> Error (Usage "observation does not exist")
  | Some _ when region = None -> Ok (Selected_observation selected_origin)
  | Some selected_observation -> (
      let local = Option.get region in
      match
        List.find_opt
          (fun candidate ->
            Observation_id.equal (Region.observation candidate)
              (Observation.id selected_observation)
            && Identifier.equal (Region.id candidate |> Region_id.local) local)
          snapshot.regions
      with
      | None -> Error (Usage "selected region does not exist in the interpreted graph")
      | Some selected_region -> (
          match Workspace_read.read ~workspace ~path:observation with
          | Error _ -> Error (Internal "selected observation cannot be read safely")
          | Ok file ->
              let expected = Observation.content_identity selected_observation in
              if
                not
                  (Option.equal Content_identity.equal expected
                     (Some (Workspace_read.content_identity file)))
              then Error (Internal "selected observation changed after graph construction")
              else
                Ok
                  (Selected_region
                     {
                       observation = selected_observation;
                       region = selected_region;
                       content = Workspace_read.content file;
                       scope = Option.value ~default:Contained scope;
                       registry;
                     })))

let query_snapshot ~workspace ~observation ~region ~scope ~registry ~direction
    ~predicate ~limit snapshot =
  let* selection =
    make_query_selection ~workspace ~observation ~region ~scope ~registry snapshot
  in
    let* occurrences =
      List.fold_left
        (fun result occurrence ->
          let* edges = result in
          let* edge =
            edge_of_occurrence ~workspace snapshot selection occurrence
          in
          Ok (match edge with None -> edges | Some edge -> edge :: edges))
        (Ok []) snapshot.occurrences
    in
    let* relations =
      List.fold_left
        (fun result relation ->
          let* edges = result in
          let* edge = edge_of_relation ~workspace snapshot selection relation in
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
        query_region = region;
        region_scope = scope;
        query_direction = direction;
        predicate;
        limit;
        matches = take limit all;
        diagnostics = snapshot.diagnostics;
        result_status =
          (if snapshot.coverage.complete then Complete else Incomplete);
        coverage = snapshot.coverage;
        truncated;
      }

let failed_query ~observation ~region ~scope ~direction ~predicate ~limit
    diagnostic =
  {
    observation;
    query_region = region;
    region_scope = scope;
    query_direction = direction;
    predicate;
    limit;
    matches = [];
    diagnostics = [ diagnostic ];
    result_status = Failed;
    coverage =
      {
        scanned_observations = 0;
        interpreted_observations = 0;
        unsupported_observations = 0;
        failed_observations = 0;
        complete = false;
      };
    truncated = false;
  }

let finish_query ~workspace ~observation ~region ~scope ~registry ~direction
    ~predicate ~limit = function
  | Ok snapshot ->
      query_snapshot ~workspace ~observation ~region ~scope ~registry ~direction
        ~predicate ~limit snapshot
  | Error (Diagnostic_error diagnostic) ->
      Ok
        (failed_query ~observation ~region ~scope ~direction ~predicate ~limit
           diagnostic)
  | Error (Query_error error) -> Error error
  | Error Unstable_workspace ->
      Error (Internal "workspace changed during graph observation")

let query ~workspace ~observation ~direction ~predicate ~limit =
  if limit <= 0 then Error (Usage "--limit must be a positive integer")
  else
    build ~workspace
    |> finish_query ~workspace ~observation ~region:None ~scope:None
         ~registry:Registry_snapshot.empty ~direction ~predicate ~limit

let query_with_registry ~workspace ~observation ~direction ~predicate ~limit
    ~registry =
  if limit <= 0 then Error (Usage "--limit must be a positive integer")
  else
    build_with_registry ~workspace ~registry
    |> finish_query ~workspace ~observation ~region:None ~scope:None ~registry
         ~direction ~predicate ~limit

let query_for_region_with_registry ~workspace ~observation ~region ~scope
    ~direction ~predicate ~limit ~registry =
  if limit <= 0 then Error (Usage "--limit must be a positive integer")
  else
    build_with_registry ~workspace ~registry
    |> finish_query ~workspace ~observation ~region:(Some region)
         ~scope:(Some scope) ~registry ~direction ~predicate ~limit

let query_for_region ~workspace ~observation ~region ~scope ~direction
    ~predicate ~limit =
  query_for_region_with_registry ~workspace ~observation ~region ~scope
    ~direction ~predicate ~limit ~registry:Registry_snapshot.empty

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
          build_with_extension ~workspace ~manifest ~executable ~arguments
          |> finish_query ~workspace ~observation ~region:None ~scope:None
               ~registry:Registry_snapshot.empty ~direction ~predicate ~limit
