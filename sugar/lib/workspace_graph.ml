type query_direction = Incoming | Outgoing | Both
type region_scope = Exact | Contained
type edge_direction = Incoming_edge | Outgoing_edge | Internal_edge
type edge_kind = Reference_use | Semantic_relation
type result_status = Complete | Incomplete | Failed

type resolution = Endpoint_resolution.t =
  | Resolved
  | Unresolved
  | Invalid_selector
  | Unreadable
  | Not_checked

type edge_target =
  | Address_target of Region_address.t
  | Unresolved_reference_target of Reference_id.t

type edge = {
  direction : edge_direction;
  kind : edge_kind;
  predicate : string;
  source : Region_address.t;
  target : edge_target;
  reference : Reference_id.t option;
  annotation : Annotation_id.t option;
  occurrence_range : Text_range.t option;
  source_resolution : resolution;
  target_resolution : resolution;
}

type coverage = Coverage.t

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
  | Unstable_workspace

type snapshot_inputs = {
  observations : Observation.t list;
  sidecar_snapshots : Sidecar_snapshot.t list;
  regions : Region.t list;
  annotation_index : Annotation_index.t;
  reference_index : Reference_index.t;
  reference_uses : Reference_use.t list;
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

let find_observation observations id =
  List.find_opt (fun observation -> Observation_id.equal id (Observation.id observation))
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

let same_sidecar_inventory left right =
  let sort = List.sort Sidecar_snapshot.compare in
  let left = sort left in
  let right = sort right in
  List.length left = List.length right
  && List.for_all2
       (fun left right -> Sidecar_snapshot.compare left right = 0)
       left right

let same_diagnostics left right =
  let sort = List.sort Diagnostic.compare in
  let left = sort left in
  let right = sort right in
  List.length left = List.length right
  && List.for_all2 (fun left right -> Diagnostic.compare left right = 0) left right

let same_scan_inventory left right =
  same_inventory (Command_result.observations left)
    (Command_result.observations right)
  && same_sidecar_inventory (Command_result.sidecar_snapshots left)
       (Command_result.sidecar_snapshots right)
  && Coverage.equal (Command_result.coverage left)
       (Command_result.coverage right)
  && same_diagnostics (Command_result.diagnostics left)
       (Command_result.diagnostics right)

let select_interpreter registry observation =
  Interpreter_dispatcher.select registry observation
  |> Result.map_error (fun message -> Query_error (Usage message))

let existing_inspection = function
  | Ok inspection -> Ok inspection
  | Error Workspace_inspect.Observation_changed -> Error Unstable_workspace
  | Error (Workspace_inspect.Invalid_observation message) ->
      Error (Query_error (Internal message))

let inspect_fixed ~registry ~observation ~sidecar_snapshots =
  Workspace_inspect.inspect_fixed_observation_with_registry ~observation
    ~sidecar_snapshots ~base_diagnostics:[] ~registry
  |> existing_inspection

let scan_workspace ~registry ~workspace =
  Workspace_scan.scan_with_classifier ~workspace
    ~classify:(Interpreter_dispatcher.classify_path registry)

let extension_target_origins reference_index reference_uses =
  let from_definitions =
    Reference_index.consistent_values reference_index
    |> List.filter_map (fun reference ->
           match Reference.target_origin (Reference.target reference) with
           | Origin.Extension _ as origin -> Some origin
           | Origin.Workspace _ | Origin.Git _ | Origin.Web _
           | Origin.Generated _ | Origin.External _ ->
               None)
  in
  let from_direct_uses =
    reference_uses
    |> List.filter_map (fun use ->
           match Reference_use.target use with
           | Reference_use.Named _ -> None
           | Reference_use.Direct address -> (
               match Region_address.origin address with
               | Origin.Extension _ as origin -> Some origin
               | Origin.Workspace _ | Origin.Git _ | Origin.Web _
               | Origin.Generated _ | Origin.External _ ->
                   None))
  in
  List.rev_append from_definitions from_direct_uses
  |> List.sort_uniq Origin.compare

let observer_diagnostic ?failure message =
  let code =
    match failure with
    | Some _ -> Diagnostic.Extension_failure
    | None -> Diagnostic.Unresolved_ref
  in
  Diagnostic.make ~code ~message ?extension_failure:failure ()

let observe_extension_origins registry origins =
  List.fold_left
    (fun result origin ->
      let* observations, diagnostics, failed = result in
      match Resource_observer_runner.observe registry origin with
      | Error message -> Error (Query_error (Usage message))
      | Ok Resource_observer_runner.Unsupported ->
          let* diagnostic =
            observer_diagnostic
              "Extension Origin has no installed Resource Observer"
            |> Result.map_error (fun message ->
                   Query_error (Internal message))
          in
          Ok (observations, diagnostic :: diagnostics, failed + 1)
      | Ok (Resource_observer_runner.Failure { failure; _ }) ->
          let* diagnostic =
            observer_diagnostic ~failure (Extension_failure.message failure)
            |> Result.map_error (fun message ->
                   Query_error (Internal message))
          in
          Ok (observations, diagnostic :: diagnostics, failed + 1)
      | Ok (Resource_observer_runner.Observed { observation; _ }) ->
          Ok (observation :: observations, diagnostics, failed))
    (Ok ([], [], 0)) origins
  |> Result.map (fun (observations, diagnostics, failed) ->
         (sort_observations observations, List.sort Diagnostic.compare diagnostics, failed))

let build_once ~registry ~workspace =
  let scan = scan_workspace ~registry ~workspace in
  match terminal_error scan with
  | Some error -> Error (Query_error error)
  | None ->
      let scanned = Command_result.observations scan |> sort_observations in
      let sidecar_snapshots = Command_result.sidecar_snapshots scan in
      let rec interpret regions reference_definitions annotation_occurrences
          reference_uses diagnostics interpreted unsupported failed
          external_observations external_origins external_diagnostics
          external_failed = function
        | [] ->
            let annotation_index =
              Annotation_index.make (List.rev annotation_occurrences)
            in
            let reference_index =
              Reference_index.make (List.rev reference_definitions)
            in
            let relations =
              Annotation_index.entries annotation_index
              |> List.filter_map (fun (_, entry) ->
                     Relation.of_index_entry entry)
            in
            let discovered_origins =
              extension_target_origins reference_index
                (List.rev reference_uses)
            in
            let new_origins =
              List.filter
                (fun origin ->
                  not
                    (List.exists (Origin.equal origin) external_origins))
                discovered_origins
            in
            if new_origins <> [] then
              let* new_observations, new_diagnostics, new_failed =
                observe_extension_origins registry new_origins
              in
              interpret regions reference_definitions annotation_occurrences
                reference_uses diagnostics interpreted unsupported
                (failed + new_failed)
                (List.rev_append new_observations external_observations)
                (List.rev_append new_origins external_origins
                |> List.sort_uniq Origin.compare)
                (List.rev_append new_diagnostics external_diagnostics)
                (external_failed + new_failed) new_observations
            else
            let scan_coverage = Command_result.coverage scan in
            let metadata_failed = Coverage.metadata_failed scan_coverage in
            let complete =
              unsupported = 0 && failed = 0 && metadata_failed = 0
              && Annotation_index.conflicts annotation_index = []
              && Reference_index.conflicts reference_index = []
            in
            let* coverage =
              Coverage.make
                ~primary_resources:
                  (Coverage.primary_resources scan_coverage
                  + List.length external_origins)
                ~observed:
                  (Coverage.observed scan_coverage
                  + List.length external_observations)
                ~interpreted
                ~unsupported ~failed
                ~metadata_discovered:
                  (Coverage.metadata_discovered scan_coverage)
                ~metadata_decoded:(Coverage.metadata_decoded scan_coverage)
                ~metadata_failed ~complete
              |> Result.map_error (fun message ->
                     Query_error (Internal message))
            in
            let final_scan = scan_workspace ~registry ~workspace in
            (match terminal_error final_scan with
            | Some error -> Error (Query_error error)
            | None ->
                if not (same_scan_inventory scan final_scan) then
                  Error Unstable_workspace
                else
                  let* final_external_observations,
                       final_external_diagnostics, final_external_failed =
                    observe_extension_origins registry external_origins
                  in
                  if
                    not
                      (same_inventory external_observations
                         final_external_observations)
                    || not
                         (same_diagnostics external_diagnostics
                            final_external_diagnostics)
                    || external_failed <> final_external_failed
                  then Error Unstable_workspace
                  else
                  Ok
                    {
                      observations =
                        sort_observations
                          (List.rev_append external_observations scanned);
                      sidecar_snapshots;
                      regions = List.rev regions;
                      annotation_index;
                      reference_index;
                      reference_uses = List.rev reference_uses;
                      relations;
                      diagnostics =
                        List.rev_append (Command_result.diagnostics scan)
                          (List.rev_append external_diagnostics diagnostics)
                        |> List.sort Diagnostic.compare;
                      coverage;
                    })
        | scanned_observation :: rest ->
                let* selected = select_interpreter registry scanned_observation in
                let unsupported =
                  match selected with None -> unsupported + 1 | Some _ -> unsupported
                in
                let* inspection =
                  inspect_fixed ~registry ~observation:scanned_observation
                    ~sidecar_snapshots
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
                          let result_diagnostics =
                            Command_result.diagnostics result
                          in
                          let has_error =
                            List.exists
                              (fun diagnostic ->
                                Diagnostic.effective_severity diagnostic
                                = Diagnostic.Error)
                              result_diagnostics
                          in
                          interpret
                            (List.rev_append
                               (Command_result.regions result)
                               regions)
                            (List.rev_append
                               (Command_result.reference_definitions result)
                               reference_definitions)
                            (List.rev_append
                               (Command_result.annotation_occurrences result)
                               annotation_occurrences)
                            (List.rev_append inspection.reference_uses reference_uses)
                            (List.rev_append result_diagnostics diagnostics)
                            (interpreted
                            + if Option.is_some inspection.interpretation then 1
                              else 0)
                            unsupported
                            (failed + if has_error then 1 else 0)
                            external_observations external_origins
                            external_diagnostics external_failed rest)
      in
      interpret [] [] [] [] [] 0 0 0 [] [] [] 0 scanned

let build_inputs ~workspace =
  match build_once ~registry:Registry_snapshot.empty ~workspace with
  | Ok snapshot -> Ok snapshot
  | Error (Query_error _ as error) -> Error error
  | Error Unstable_workspace -> (
      match build_once ~registry:Registry_snapshot.empty ~workspace with
      | Ok snapshot -> Ok snapshot
      | Error (Query_error _ as error) -> Error error
      | Error Unstable_workspace ->
          Error
            (Query_error
               (Internal "workspace changed during graph observation")))

let build_inputs_with_registry ~workspace ~registry =
  match build_once ~registry ~workspace with
  | Ok snapshot -> Ok snapshot
  | Error (Query_error _ as error) -> Error error
  | Error Unstable_workspace -> (
      match
        build_once ~registry ~workspace
      with
      | Ok snapshot -> Ok snapshot
      | Error (Query_error _ as error) -> Error error
      | Error Unstable_workspace ->
          Error
            (Query_error
               (Internal "workspace changed during graph observation")))

let build_inputs_with_extension ~workspace ~manifest ~executable ~arguments =
  let* extension =
    Installed_extension.make ~manifest ~executable ~arguments
    |> Result.map_error (fun message -> Query_error (Usage message))
  in
  let* registry =
    Registry_snapshot.make [ extension ]
    |> Result.map_error (fun message -> Query_error (Usage message))
  in
  build_inputs_with_registry ~workspace ~registry

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
  match Reference_use.source_region occurrence with
  | Reference_use.Region id -> address_of_region_id snapshot id
  | Reference_use.Whole_observation ->
      let* origin =
        origin_of_observation_id snapshot
          (Reference_use.source_observation occurrence)
      in
      Region_address.make ~origin:origin ~selector:Selector.Whole_observation ()
      |> Result.map_error (fun message -> Internal message)

let find_reference snapshot id =
  match Reference_index.find id snapshot.reference_index with
  | Some (Reference_index.Consistent { value; _ }) -> Some value
  | Some (Reference_index.Conflict _) | None -> None

let find_observation_by_origin snapshot origin =
  List.find_opt
    (fun observation ->
      Observation.compare_origin origin (Observation.origin observation) = 0)
    snapshot.observations

let region_matches_address observation address region =
  Observation_id.equal (Observation.id observation) (Region.observation region)
  && Selector.compare (Region.selector region)
       (Region_address.selector address)
     = 0
  &&
  match Region_address.interpreter_identity address with
  | None -> true
  | Some expected -> (
      match Region.interpreter_identity region with
      | Some actual -> Interpreter.equal expected actual
      | None -> false)

let address_resolution snapshot address =
  match Region_address.origin address with
  | (Origin.Workspace _ | Origin.Extension _) as origin -> (
      match find_observation_by_origin snapshot origin with
      | None -> Unresolved
      | Some observation -> (
      match Region_address.selector address with
      | Selector.Whole_observation -> Resolved
      | Selector.Region_id local ->
          if
            List.exists
              (fun region ->
                Observation_id.equal (Observation.id observation)
                  (Region.observation region)
                && Identifier.equal local (Region.id region |> Region_id.local)
                &&
                match Region_address.interpreter_identity address with
                | None -> true
                | Some expected -> (
                    match Region.interpreter_identity region with
                    | Some actual -> Interpreter.equal expected actual
                    | None -> false))
              snapshot.regions
          then Resolved
          else Unresolved
      | Selector.Text_range range -> (
          match Observation.bytes observation with
          | Some content when Text_range.end_ range <= String.length content ->
              Resolved
          | Some _ -> Invalid_selector
          | None -> Unreadable)
      | Selector.Row_filter filter -> (
          match
            ( Region_address.interpreter_identity address,
              Observation.bytes observation )
          with
          | Some interpreter, Some content
            when String.equal (Interpreter.name interpreter) "jsonl"
                 && String.equal (Interpreter.version interpreter) "1" -> (
              match Jsonl_interpreter.select filter content with
              | Ok (Jsonl_interpreter.One _) -> Resolved
              | Ok Jsonl_interpreter.No_match -> Unresolved
              | Ok Jsonl_interpreter.Ambiguous | Error _ -> Invalid_selector)
          | Some _, Some _ -> Invalid_selector
          | _, None -> Unreadable
          | None, Some _ -> Invalid_selector)
      | Selector.Extension _ ->
          if
            List.exists (region_matches_address observation address)
              snapshot.regions
          then Resolved
          else Unresolved))
  | Origin.Git _
  | Origin.Web _
  | Origin.Generated _
  | Origin.External _ ->
      Not_checked

let reference_resolution snapshot reference =
  address_resolution snapshot (Reference.target reference)

let direct_resolution = address_resolution

let target_of_occurrence snapshot occurrence =
  match Reference_use.target occurrence with
  | Reference_use.Direct address ->
      Ok (Address_target address, None, direct_resolution snapshot address)
  | Reference_use.Named id -> (
      match find_reference snapshot id with
      | None -> Ok (Unresolved_reference_target id, Some id, Unresolved)
      | Some reference ->
          Ok
            ( Address_target (Reference.target reference),
              Some id,
              reference_resolution snapshot reference ))

let reference_edge_of_occurrence snapshot occurrence =
  let* source = source_of_occurrence snapshot occurrence in
  let* target, _, target_resolution =
    target_of_occurrence snapshot occurrence
  in
  let target =
    match target with
    | Address_target address -> Reference_edge.Address address
    | Unresolved_reference_target reference ->
        Reference_edge.Unresolved_reference reference
  in
  Ok
    (Reference_edge.make ~source ~target
       ~source_resolution:(direct_resolution snapshot source)
       ~target_resolution ~use:occurrence)

let finalize_snapshot inputs =
  let* reference_edges =
    List.fold_left
      (fun result occurrence ->
        let* edges = result in
        let* edge = reference_edge_of_occurrence inputs occurrence in
        Ok (edge :: edges))
      (Ok []) inputs.reference_uses
  in
  Ok
    (Workspace_graph_snapshot.make ~observations:inputs.observations
       ~sidecar_snapshots:inputs.sidecar_snapshots ~regions:inputs.regions
       ~annotation_index:inputs.annotation_index
       ~reference_index:inputs.reference_index
       ~reference_uses:inputs.reference_uses ~relations:inputs.relations
       ~reference_edges:(List.rev reference_edges)
       ~diagnostics:inputs.diagnostics ~coverage:inputs.coverage)

let inputs_of_snapshot snapshot =
  {
    observations = Workspace_graph_snapshot.observations snapshot;
    sidecar_snapshots = Workspace_graph_snapshot.sidecar_snapshots snapshot;
    regions = Workspace_graph_snapshot.regions snapshot;
    annotation_index = Workspace_graph_snapshot.annotation_index snapshot;
    reference_index = Workspace_graph_snapshot.reference_index snapshot;
    reference_uses = Workspace_graph_snapshot.reference_uses snapshot;
    relations = Workspace_graph_snapshot.relations snapshot;
    diagnostics = Workspace_graph_snapshot.diagnostics snapshot;
    coverage = Workspace_graph_snapshot.coverage snapshot;
  }

let resolve_address snapshot address =
  address_resolution (inputs_of_snapshot snapshot) address

let target_observation snapshot address =
  match resolve_address snapshot address with
  | Resolved ->
      find_observation_by_origin
        (inputs_of_snapshot snapshot)
        (Region_address.origin address)
  | Unresolved | Invalid_selector | Unreadable | Not_checked -> None

let snapshot_result = function
  | Ok inputs -> finalize_snapshot inputs
  | Error (Query_error error) -> Error error
  | Error Unstable_workspace ->
      Error (Internal "workspace changed during graph observation")

let build_snapshot ~workspace =
  build_inputs ~workspace |> snapshot_result

let build_snapshot_with_registry ~workspace ~registry =
  build_inputs_with_registry ~workspace ~registry |> snapshot_result

let build = build_inputs
let build_with_registry = build_inputs_with_registry
let build_with_extension = build_inputs_with_extension

let endpoint_origin address = Region_address.origin address

type query_selection =
  | Selected_observation of Origin.t
  | Selected_region of {
      observation : Observation.t;
      region : Region.t;
      scope : region_scope;
      registry : Registry_snapshot.t;
    }

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
             ~observation:selected.observation ~left:selected.region
             ~right:endpoint
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
  let* target_matches =
    match target with
    | Address_target address -> endpoint_matches snapshot selection address
    | Unresolved_reference_target _ -> Ok false
  in
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

let edge_of_reference_edge snapshot selection reference_edge =
  let source = Reference_edge.source reference_edge in
  let target =
    match Reference_edge.target reference_edge with
    | Reference_edge.Address address -> Address_target address
    | Reference_edge.Unresolved_reference reference ->
        Unresolved_reference_target reference
  in
  let* direction = classify_direction snapshot selection source target in
  match direction with
  | None -> Ok None
  | Some direction ->
      let use = Reference_edge.use reference_edge in
      let reference =
        match Reference_use.target use with
        | Reference_use.Named reference -> Some reference
        | Reference_use.Direct _ -> None
      in
      Ok
        (Some
           {
             direction;
             kind = Reference_use;
             predicate = "references";
             source;
             target;
             reference;
             annotation = None;
             occurrence_range = Some (Reference_use.source_range use);
             source_resolution = Reference_edge.source_resolution reference_edge;
             target_resolution = Reference_edge.target_resolution reference_edge;
           })

let target_of_relation snapshot relation =
  match Relation.object_ relation with
  | Relation.Region region ->
      let* address = address_of_region_ref snapshot region in
      Ok (Address_target address, None, direct_resolution snapshot address)
  | Relation.Reference id -> (
      match find_reference snapshot id with
      | None -> Ok (Unresolved_reference_target id, Some id, Unresolved)
      | Some reference ->
          Ok
            ( Address_target (Reference.target reference),
              Some id,
              reference_resolution snapshot reference ))

let edge_of_relation snapshot selection relation =
  match Relation.subject relation with
  | Relation.Reference _ ->
      Error (Internal "standard annotation relation has a reference subject")
  | Relation.Region subject ->
      let* source = address_of_region_ref snapshot subject in
      let* target, reference, resolution =
        target_of_relation snapshot relation
      in
      let* direction = classify_direction snapshot selection source target in
      (match direction with
      | None -> Ok None
      | Some direction ->
          Ok
            (Some
               {
                 direction;
                 kind = Semantic_relation;
                 predicate = Relation.predicate relation;
                 source;
                 target;
                 reference;
                 annotation = Some (Relation.id relation);
                 occurrence_range = None;
                 source_resolution = direct_resolution snapshot source;
                 target_resolution = resolution;
               }))

let direction_rank = function
  | Outgoing_edge -> 0
  | Incoming_edge -> 1
  | Internal_edge -> 2

let kind_rank = function Reference_use -> 0 | Semantic_relation -> 1

let compare_target left right =
  match left, right with
  | Address_target left, Address_target right -> Region_address.compare left right
  | Unresolved_reference_target left, Unresolved_reference_target right ->
      Reference_id.compare left right
  | Address_target _, Unresolved_reference_target _ -> -1
  | Unresolved_reference_target _, Address_target _ -> 1

let compare_optional compare left right = Option.compare compare left right

let compare_edge left right =
  match Int.compare (direction_rank left.direction) (direction_rank right.direction) with
  | 0 -> (
      match String.compare left.predicate right.predicate with
      | 0 -> (
          match Region_address.compare left.source right.source with
          | 0 -> (
              match compare_target left.target right.target with
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

let make_query_selection ~workspace:_ ~observation ~region ~scope ~registry
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
      | Some selected_region ->
          Ok
            (Selected_region
               {
                 observation = selected_observation;
                 region = selected_region;
                 scope = Option.value ~default:Contained scope;
                 registry;
               }))

let query_snapshot ~workspace ~observation ~region ~scope ~registry ~direction
    ~predicate ~limit snapshot =
  let* graph = finalize_snapshot snapshot in
  let* selection =
    make_query_selection ~workspace ~observation ~region ~scope ~registry snapshot
  in
    let* occurrences =
      List.fold_left
        (fun result occurrence ->
          let* edges = result in
          let* edge =
            edge_of_reference_edge snapshot selection occurrence
          in
          Ok (match edge with None -> edges | Some edge -> edge :: edges))
        (Ok []) (Workspace_graph_snapshot.reference_edges graph)
    in
    let* relations =
      List.fold_left
        (fun result relation ->
          let* edges = result in
          let* edge = edge_of_relation snapshot selection relation in
          Ok (match edge with None -> edges | Some edge -> edge :: edges))
        (Ok []) (Workspace_graph_snapshot.relations graph)
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
        diagnostics = Workspace_graph_snapshot.diagnostics graph;
        result_status =
          (if Coverage.complete (Workspace_graph_snapshot.coverage graph) then
             Complete
           else Incomplete);
        coverage = Workspace_graph_snapshot.coverage graph;
        truncated;
      }

let finish_query ~workspace ~observation ~region ~scope ~registry ~direction
    ~predicate ~limit = function
  | Ok snapshot ->
      query_snapshot ~workspace ~observation ~region ~scope ~registry ~direction
        ~predicate ~limit snapshot
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
