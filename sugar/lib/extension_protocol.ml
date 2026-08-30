type interpret_result =
  | Interpretation of Interpretation.t
  | Interpret_failure of Extension_failure.t

type observe_result =
  | Observed of Observation.t
  | Observe_failure of Extension_failure.t

type extract_references_result =
  | Reference_extraction of Reference_extraction.t
  | Extract_references_failure of Extension_failure.t

type extract_annotations_result =
  | Annotation_extraction of Annotation_extraction.t
  | Extract_annotations_failure of Extension_failure.t

type resolve_result =
  | Resolved_region of Region.t
  | Resolve_failure of Extension_failure.t

type classify_result =
  | Classified of Region_extent_relation.t
  | Classify_failure of Extension_failure.t

type audit_result =
  | Audit_diagnostics of Diagnostic.t list
  | Audit_failure of Extension_failure.t

type derive_result =
  | Derived_patches of Proposed_patch.t list
  | Derive_failure of Extension_failure.t

let ( let* ) = Result.bind
let ( >>= ) = Result.bind

let interpret_params ~observation =
  let observation_json =
    observation |> Normal.Observation.normalize |> Normal_json.observation
  in
  `Assoc [ ("observation", observation_json) ]

let observe_resource_params ~origin =
  `Assoc
    [
      ("origin", origin |> Normal.Origin.normalize |> Normal_json.origin);
    ]

let interpreter_json interpreter =
  `Assoc
    [
      ("name", `String (Interpreter.name interpreter));
      ("version", `String (Interpreter.version interpreter));
    ]

let interpretation_json interpretation =
  `Assoc
    [
      ("interpreter", interpreter_json (Interpretation.interpreter interpretation));
      ( "observation",
        `String
          (Interpretation.observation interpretation
          |> Observation_id.to_string) );
      ( "regions",
        `List
          (Interpretation.regions interpretation
          |> List.map (fun region ->
                 region |> Normal.Region.normalize |> Normal_json.region)) );
    ]

let extract_references_params ~observation ~interpretation =
  let observation_json =
    observation |> Normal.Observation.normalize |> Normal_json.observation
  in
  `Assoc
    [
      ("observation", observation_json);
      ("interpretation", interpretation_json interpretation);
    ]

let extract_annotations_params = extract_references_params

let resolve_params ~observation ~selector =
  let observation_json =
    observation |> Normal.Observation.normalize |> Normal_json.observation
  in
  let selector_json =
    selector |> Normal.Selector.normalize |> Normal_json.selector
  in
  `Assoc
    [
      ("observation", observation_json);
      ("selector", selector_json);
    ]

let classify_region_extents_params ~observation ~left ~right =
  let observation_identity = Observation.identity observation in
  if
    not
      (Observation_id.equal (Observation.id observation)
         (Region.observation left))
    || not
         (Observation_id.equal (Observation.id observation)
            (Region.observation right))
    || not
      (Observation_identity.equal observation_identity
         (Region.observation_identity left))
    || not
         (Observation_identity.equal observation_identity
            (Region.observation_identity right))
  then Error "both regions must belong to the supplied observation"
  else
    Ok
      (`Assoc
        [
          ( "observation",
            observation |> Normal.Observation.normalize
            |> Normal_json.observation );
          ("left", left |> Normal.Region.normalize |> Normal_json.region);
          ("right", right |> Normal.Region.normalize |> Normal_json.region);
        ])

let audit_params ~snapshot ~policy =
  `Assoc
    [
      ("snapshot", Workspace_graph_json.snapshot snapshot);
      ("policy", Audit_policy_json.encode policy);
    ]

let derive_params ~request ~snapshot =
  `Assoc
    [
      ("request", Derive_request_json.encode request);
      ("snapshot", Workspace_graph_json.snapshot snapshot);
    ]

let duplicate_name fields =
  let names = List.map fst fields |> List.sort String.compare in
  let rec loop = function
    | left :: (right :: _ as rest) ->
        String.equal left right || loop rest
    | [] | [ _ ] -> false
  in
  loop names

let type_name = function
  | `Assoc _ -> "object"
  | `Bool _ -> "boolean"
  | `Float _ -> "float"
  | `Int _ | `Intlit _ -> "integer"
  | `List _ -> "array"
  | `Null -> "null"
  | `String _ -> "string"
  | `Tuple _ -> "tuple"
  | `Variant _ -> "variant"

let error path message = Error (path ^ ": " ^ message)
let field path name = path ^ "." ^ name
let index_path path value = Printf.sprintf "%s[%d]" path value

let object_fields path allowed = function
  | `Assoc fields when duplicate_name fields ->
      error path "object field names must be unique"
  | `Assoc fields -> (
      match List.find_opt (fun (name, _) -> not (List.mem name allowed)) fields with
      | Some (name, _) -> error path ("unknown field: " ^ name)
      | None -> Ok fields)
  | json -> error path ("expected object, got " ^ type_name json)

let object_fields_any path = function
  | `Assoc fields when duplicate_name fields ->
      error path "object field names must be unique"
  | `Assoc fields -> Ok fields
  | json -> error path ("expected object, got " ^ type_name json)

let require fields path name =
  match List.assoc_opt name fields with
  | Some value -> Ok value
  | None -> error path ("missing field: " ^ name)

let optional fields name = List.assoc_opt name fields

let require_only path fields allowed =
  match List.find_opt (fun (name, _) -> not (List.mem name allowed)) fields with
  | Some (name, _) -> error path ("field is not allowed for this variant: " ^ name)
  | None -> Ok ()

let string path = function
  | `String value when Utf8.is_valid value -> Ok value
  | `String _ -> error path "string must be valid UTF-8"
  | json -> error path ("expected string, got " ^ type_name json)

let list path decode = function
  | `List values ->
      let rec loop index accumulated = function
        | [] -> Ok (List.rev accumulated)
        | value :: rest ->
            let* decoded = decode (index_path path index) value in
            loop (index + 1) (decoded :: accumulated) rest
      in
      loop 0 [] values
  | json -> error path ("expected array, got " ^ type_name json)

let bind_construct path = function
  | Ok value -> Ok value
  | Error message -> error path message

let scoped_id path make json =
  let* fields = object_fields path [ "observation"; "local" ] json in
  let* observation = require fields path "observation" in
  let* observation = string (field path "observation") observation in
  let* observation = Observation_id.make observation |> bind_construct (field path "observation") in
  let* local = require fields path "local" in
  let* local = string (field path "local") local in
  make ~observation ~local |> bind_construct path

let region_id path json = scoped_id path Region_id.make json

let range path json =
  Normal_decode.text_range json |> Result.map_error (fun message -> path ^ ": " ^ message)

let workspace_path path json =
  Normal_decode.workspace_path json
  |> Result.map_error (fun message -> path ^ ": " ^ message)

let origin path json =
  let* fields =
    object_fields path
      [ "kind"; "path"; "repo"; "rev"; "url"; "name"; "uri"; "observer"; "locator" ]
      json
  in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  match kind with
  | "workspace" ->
      let* () = require_only path fields [ "kind"; "path" ] in
      let* value = require fields path "path" >>= workspace_path (field path "path") in
      Ok (Observation.workspace value)
  | "git" ->
      let* () = require_only path fields [ "kind"; "repo"; "rev"; "path" ] in
      let* repo = require fields path "repo" >>= string (field path "repo") in
      let* path_value = require fields path "path" >>= string (field path "path") in
      let* rev =
        match optional fields "rev" with
        | None -> Ok None
        | Some value -> Result.map Option.some (string (field path "rev") value)
      in
      Observation.git ~repo ?rev ~path:path_value () |> bind_construct path
  | "web" ->
      let* () = require_only path fields [ "kind"; "url" ] in
      let* url = require fields path "url" >>= string (field path "url") in
      Observation.web url |> bind_construct path
  | "generated" ->
      let* () = require_only path fields [ "kind"; "name" ] in
      let* name = require fields path "name" >>= string (field path "name") in
      Observation.generated name |> bind_construct path
  | "external" ->
      let* () = require_only path fields [ "kind"; "uri" ] in
      let* uri = require fields path "uri" >>= string (field path "uri") in
      Observation.external_ uri |> bind_construct path
  | "extension" ->
      let* () = require_only path fields [ "kind"; "observer"; "locator" ] in
      let observer_path = field path "observer" in
      let* observer_fields =
        require fields path "observer"
        >>= object_fields observer_path [ "name"; "version" ]
      in
      let* observer_name =
        require observer_fields observer_path "name"
        >>= string (field observer_path "name")
      in
      let* observer_version =
        require observer_fields observer_path "version"
        >>= string (field observer_path "version")
      in
      let* observer =
        Resource_observer.make ~name:observer_name ~version:observer_version ()
        |> bind_construct observer_path
      in
      let* locator = require fields path "locator" in
      Observation.extension ~observer ~locator () |> bind_construct path
  | _ -> error (field path "kind") "unsupported origin kind"

let observation_type path json =
  let* fields = object_fields path [ "name"; "version" ] json in
  let* name = require fields path "name" >>= string (field path "name") in
  let* version =
    require fields path "version" >>= string (field path "version")
  in
  Observation_type.make ~name ~version () |> bind_construct path

let observation_identity path json =
  let* fields = object_fields path [ "observationType"; "key" ] json in
  let* observation_type =
    require fields path "observationType"
    >>= observation_type (field path "observationType")
  in
  let* key = require fields path "key" >>= string (field path "key") in
  Observation_identity.make ~observation_type ~key () |> bind_construct path

type decoded_representation =
  | Byte_representation
  | Structured_representation of {
      schema : string;
      value : Yojson.Safe.t;
    }

let observation_representation path json =
  let* fields = object_fields path [ "kind"; "schema"; "value" ] json in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  match kind with
  | "bytes" ->
      let* () = require_only path fields [ "kind" ] in
      Ok Byte_representation
  | "structured" ->
      let* () = require_only path fields [ "kind"; "schema"; "value" ] in
      let* schema =
        require fields path "schema" >>= string (field path "schema")
      in
      let* value = require fields path "value" in
      Ok (Structured_representation { schema; value })
  | _ -> error (field path "kind") "unsupported Observation representation"

let decode_observation ~manifest ~requested_origin ~content path json =
  let* fields =
    object_fields path
      [ "id"; "origin"; "identity"; "representation"; "contentIdentity" ]
      json
  in
  let* id = require fields path "id" >>= string (field path "id") in
  let* id = Observation_id.make id |> bind_construct (field path "id") in
  let* decoded_origin =
    require fields path "origin" >>= origin (field path "origin")
  in
  let* () =
    if Origin.equal requested_origin decoded_origin then Ok ()
    else error (field path "origin") "must equal the requested Origin"
  in
  let* identity =
    require fields path "identity"
    >>= observation_identity (field path "identity")
  in
  let* representation =
    require fields path "representation"
    >>= observation_representation (field path "representation")
  in
  let observation_type = Observation_identity.observation_type identity in
  let capability = Extension_manifest.capability manifest in
  let* () =
    match Capability.applies_to capability with
    | Some applies_to
      when List.exists (Observation_type.equal observation_type)
             applies_to.observation_types ->
        Ok ()
    | Some _ ->
        error (field path "identity.observationType")
          "is not declared by the Resource Observer manifest"
    | None -> error "$manifest.capability" "has no ObservationType contract"
  in
  match representation, content, optional fields "contentIdentity" with
  | Byte_representation, Some bytes, Some declared_identity ->
      let* declared_identity =
        Normal_decode.content_identity declared_identity
        |> Result.map_error (fun message ->
               field path "contentIdentity" ^ ": " ^ message)
      in
      let actual_identity = Content_identity.of_content bytes in
      if not (Content_identity.equal declared_identity actual_identity) then
        error (field path "contentIdentity")
          "does not match the streamed Observation bytes"
      else
        Observation.make ~id ~origin:decoded_origin ~identity
          ~representation:(Observation.Bytes bytes) ()
        |> bind_construct path
  | Byte_representation, None, _ ->
      error (field path "representation")
        "byte Observation requires an extension-to-host content stream"
  | Byte_representation, Some _, None ->
      error path "byte Observation requires contentIdentity"
  | Structured_representation { schema; value }, None, None ->
      Observation.of_structured ~id ~origin:decoded_origin ~identity ~schema
        ~value ()
      |> bind_construct path
  | Structured_representation _, Some _, _ ->
      error (field path "representation")
        "structured Observation must not stream byte content"
  | Structured_representation _, None, Some _ ->
      error path "structured Observation must not contain contentIdentity"

let origin_scoped_id path make json =
  let* fields = object_fields path [ "scope"; "local" ] json in
  let* scope = require fields path "scope" >>= origin (field path "scope") in
  let* local = require fields path "local" >>= string (field path "local") in
  make ~scope ~local |> bind_construct path

let reference_id path json = origin_scoped_id path Reference_id.make json
let annotation_id path json = origin_scoped_id path Annotation_id.make json

let selector_literal path = function
  | `String value when Utf8.is_valid value -> Ok (Selector.Literal.String value)
  | `String _ -> error path "string must be valid UTF-8"
  | `Int value when Protocol_integer.is_safe value -> Ok (Selector.Literal.Int value)
  | `Int _ | `Intlit _ -> error path "integer exceeds the protocol safe range"
  | `Bool value -> Ok (Selector.Literal.Bool value)
  | json -> error path ("expected selector literal, got " ^ type_name json)

let selector path json =
  let* fields =
    object_fields path [ "kind"; "id"; "range"; "where"; "schema"; "value" ] json
  in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  match kind with
  | "whole-observation" ->
      let* () = require_only path fields [ "kind" ] in
      Ok Selector.Whole_observation
  | "region-id" ->
      let* () = require_only path fields [ "kind"; "id" ] in
      let* id = require fields path "id" >>= string (field path "id") in
      Identifier.make id |> Result.map (fun id -> Selector.Region_id id)
      |> bind_construct path
  | "text-range" ->
      let* () = require_only path fields [ "kind"; "range" ] in
      let* range_value = require fields path "range" >>= range (field path "range") in
      Ok (Selector.Text_range range_value)
  | "row-filter" ->
      let* () = require_only path fields [ "kind"; "where" ] in
      let* where = require fields path "where" in
      let* where_fields = object_fields_any (field path "where") where in
      let* conditions =
        where_fields
        |> List.fold_left
             (fun result (name, value) ->
               let* conditions = result in
               let* field_name =
                 Selector.Field_name.make name
                 |> bind_construct (field path ("where." ^ name))
               in
               let* literal =
                 selector_literal (field path ("where." ^ name)) value
               in
               Ok ((field_name, literal) :: conditions))
             (Ok [])
      in
      Selector.Row_filter.make conditions
      |> Result.map (fun value -> Selector.Row_filter value)
      |> bind_construct path
  | "extension" ->
      let* () = require_only path fields [ "kind"; "schema"; "value" ] in
      let* schema = require fields path "schema" >>= string (field path "schema") in
      let* value = require fields path "value" in
      Selector.extension ~schema ~value |> bind_construct path
  | _ -> error (field path "kind") "unsupported selector kind"

let interpreter_of_manifest manifest =
  let capability = Extension_manifest.capability manifest in
  Interpreter.make ~name:(Capability.name capability)
    ~version:(Capability.version capability) ()

let optional_interpreter path fields =
  match (optional fields "interpreter", optional fields "interpreterVersion") with
  | None, None -> Ok None
  | Some name, Some version ->
      let* name = string (field path "interpreter") name in
      let* version = string (field path "interpreterVersion") version in
      Interpreter.make ~name ~version ()
      |> Result.map Option.some |> bind_construct path
  | Some _, None | None, Some _ ->
      error path "interpreter and interpreterVersion must occur together"

let region ~manifest ~identities path json =
  let* fields =
    object_fields path
      [ "id"; "selector"; "interpreter"; "interpreterVersion"; "summary"; "range"; "fingerprint" ]
      json
  in
  let* id = require fields path "id" >>= region_id (field path "id") in
  let observation_id = Region_id.observation id in
  let* observation_identity =
    match
      List.find_opt
        (fun (candidate, _) -> Observation_id.equal candidate observation_id)
        identities
    with
    | Some (_, identity) -> Ok identity
    | None ->
        error (field path "id")
          "region observation does not match the interpreted observation"
  in
  let* selector = require fields path "selector" >>= selector (field path "selector") in
  let* summary =
    match optional fields "summary" with
    | None -> Ok None
    | Some value -> Result.map Option.some (string (field path "summary") value)
  in
  let* range =
    match optional fields "range" with
    | None -> Ok None
    | Some value -> Result.map Option.some (range (field path "range") value)
  in
  let* fingerprint =
    match optional fields "fingerprint" with
    | None -> Ok None
    | Some value -> Result.map Option.some (string (field path "fingerprint") value)
  in
  match selector with
  | Selector.Whole_observation ->
      if optional fields "interpreter" <> None || optional fields "interpreterVersion" <> None then
        error path "whole-observation region must not specify an interpreter"
      else Ok (Region.whole ~id ~observation_identity)
  | _ ->
      let* manifest_interpreter =
        interpreter_of_manifest manifest |> bind_construct path
      in
      let* interpreter =
        match optional_interpreter path fields with
        | Error _ as error -> error
        | Ok None -> Ok manifest_interpreter
        | Ok (Some explicit) ->
            if Interpreter.equal explicit manifest_interpreter then Ok explicit
            else error path "region interpreter must match the extension manifest"
      in
      Region.make ~id ~observation_identity ~selector ~interpreter ?summary
        ?range ?fingerprint ()
      |> bind_construct path

let region_address path json =
  let* fields =
    object_fields path
      [ "origin"; "selector"; "interpreter"; "interpreterVersion" ] json
  in
  let* origin = require fields path "origin" >>= origin (field path "origin") in
  let* selector = require fields path "selector" >>= selector (field path "selector") in
  let* interpreter =
    match optional fields "interpreter" with
    | None -> Ok None
    | Some value -> Result.map Option.some (string (field path "interpreter") value)
  in
  let* interpreter_version =
    match optional fields "interpreterVersion" with
    | None -> Ok None
    | Some value ->
        Result.map Option.some (string (field path "interpreterVersion") value)
  in
  Region_address.make ~origin ~selector ?interpreter ?interpreter_version ()
  |> bind_construct path

let region_ref path json =
  let* fields = object_fields path [ "kind"; "id"; "address" ] json in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  match kind with
  | "resolved" ->
      let* () = require_only path fields [ "kind"; "id" ] in
      let* id = require fields path "id" >>= region_id (field path "id") in
      Ok (Region_ref.Resolved id)
  | "address" ->
      let* () = require_only path fields [ "kind"; "address" ] in
      let* address =
        require fields path "address" >>= region_address (field path "address")
      in
      Ok (Region_ref.Address address)
  | _ -> error (field path "kind") "unsupported region reference kind"

let expectation path json =
  let* fields = object_fields path [ "kind"; "digest" ] json in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  match kind with
  | "digest" ->
      let* () = require_only path fields [ "kind"; "digest" ] in
      let* digest = require fields path "digest" >>= string (field path "digest") in
      let prefix = "sha256:" in
      if not (String.starts_with ~prefix digest) then
        error (field path "digest") "digest must start with sha256:"
      else
        let hex =
          String.sub digest (String.length prefix)
            (String.length digest - String.length prefix)
        in
        Content_digest.of_hex hex
        |> Result.map (fun digest -> Expectation.Digest digest)
        |> bind_construct (field path "digest")
  | _ -> error (field path "kind") "unsupported expectation kind"

let binding path value =
  match value with
  | "pinned" -> Ok Reference.Pinned
  | "tracking" -> Ok Reference.Tracking
  | "floating" -> Ok Reference.Floating
  | _ -> error path "unsupported reference binding"

let reference path json =
  let* fields =
    object_fields path [ "id"; "target"; "binding"; "expectations" ] json
  in
  let* id = require fields path "id" >>= reference_id (field path "id") in
  let* target = require fields path "target" >>= region_address (field path "target") in
  let* binding =
    require fields path "binding" >>= string (field path "binding")
    >>= binding (field path "binding")
  in
  let* expectations =
    require fields path "expectations"
    >>= list (field path "expectations") expectation
  in
  Ok (Reference.make ~id ~target ~binding ~expectations ())

let reference_use_target path json =
  let* fields = object_fields path [ "kind"; "reference"; "address" ] json in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  match kind with
  | "named" ->
      let* () = require_only path fields [ "kind"; "reference" ] in
      let* id =
        require fields path "reference"
        >>= reference_id (field path "reference")
      in
      Ok (Reference_use.Named id)
  | "direct" ->
      let* () = require_only path fields [ "kind"; "address" ] in
      let* address =
        require fields path "address"
        >>= region_address (field path "address")
      in
      Ok (Reference_use.Direct address)
  | _ -> error (field path "kind") "unsupported reference-use target kind"

let reference_use_source_region path json =
  let* fields = object_fields path [ "kind"; "id" ] json in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  match kind with
  | "whole-observation" ->
      let* () = require_only path fields [ "kind" ] in
      Ok Reference_use.Whole_observation
  | "region" ->
      let* () = require_only path fields [ "kind"; "id" ] in
      let* id = require fields path "id" >>= region_id (field path "id") in
      Ok (Reference_use.Region id)
  | _ -> error (field path "kind") "unsupported reference-use source region"

let reference_use path json =
  let* fields =
    object_fields path
      [ "sourceObservation"; "sourceRegion"; "sourceRange"; "target" ] json
  in
  let* source_observation =
    require fields path "sourceObservation"
    >>= string (field path "sourceObservation")
    >>= fun value ->
    Observation_id.make value |> bind_construct (field path "sourceObservation")
  in
  let* source_region =
    require fields path "sourceRegion"
    >>= reference_use_source_region (field path "sourceRegion")
  in
  let* source_range =
    require fields path "sourceRange" >>= range (field path "sourceRange")
  in
  let* target =
    require fields path "target"
    >>= reference_use_target (field path "target")
  in
  Reference_use.make ~source_observation ~source_region ~source_range ~target
  |> bind_construct path

let structured_location path json =
  let* fields = object_fields path [ "schema"; "value" ] json in
  let* schema = require fields path "schema" >>= string (field path "schema") in
  let* value = require fields path "value" in
  Structured_location.make ~schema ~value |> bind_construct path

let source_location path json =
  let* fields =
    object_fields path [ "kind"; "observation"; "locator"; "encoding" ] json
  in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  if not (String.equal kind "observation") then
    error (field path "kind") "extractor source must be an observation"
  else
    let* observation =
      require fields path "observation" >>= string (field path "observation")
      >>= fun value ->
      Observation_id.make value |> bind_construct (field path "observation")
    in
    let* locator_fields =
      require fields path "locator"
      >>= object_fields_any (field path "locator")
    in
    let* locator_kind =
      require locator_fields (field path "locator") "kind"
      >>= string (field (field path "locator") "kind")
    in
    let* locator =
      match locator_kind with
      | "byte-range" ->
          let* () =
            require_only (field path "locator") locator_fields [ "kind"; "range" ]
          in
          let* value =
            require locator_fields (field path "locator") "range"
            >>= range (field (field path "locator") "range")
          in
          Ok (Source_location.Byte_range value)
      | "structured" ->
          let* () =
            require_only (field path "locator") locator_fields
              [ "kind"; "location" ]
          in
          let* value =
            require locator_fields (field path "locator") "location"
            >>= structured_location (field (field path "locator") "location")
          in
          Ok (Source_location.Structured value)
      | _ ->
          error (field (field path "locator") "kind")
            "unsupported observation source locator"
    in
    let* encoding_fields =
      require fields path "encoding"
      >>= object_fields (field path "encoding") [ "name"; "version" ]
    in
    let* name =
      require encoding_fields (field path "encoding") "name"
      >>= string (field (field path "encoding") "name")
    in
    let* version =
      require encoding_fields (field path "encoding") "version"
      >>= string (field (field path "encoding") "version")
    in
    let* encoding =
      Observation_encoding.make ~name ~version |> bind_construct (field path "encoding")
    in
    Ok (Source_location.in_observation ~observation ~locator ~encoding)

let annotation_object path json =
  let* fields = object_fields path [ "kind"; "region"; "reference"; "value" ] json in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  match kind with
  | "region" ->
      let* () = require_only path fields [ "kind"; "region" ] in
      let* region =
        require fields path "region" >>= region_ref (field path "region")
      in
      Ok (Annotation.Region_object region)
  | "reference" ->
      let* () = require_only path fields [ "kind"; "reference" ] in
      let* reference =
        require fields path "reference"
        >>= reference_id (field path "reference")
      in
      Ok (Annotation.Reference_object reference)
  | "literal" ->
      let* () = require_only path fields [ "kind"; "value" ] in
      let* value = require fields path "value" >>= string (field path "value") in
      Ok (Annotation.Literal value)
  | _ -> error (field path "kind") "unsupported annotation object kind"

let annotation path json =
  let* fields = object_fields path [ "id"; "subject"; "predicate"; "object" ] json in
  let* id = require fields path "id" >>= annotation_id (field path "id") in
  let* subject =
    require fields path "subject" >>= region_ref (field path "subject")
  in
  let* predicate =
    require fields path "predicate" >>= string (field path "predicate")
  in
  let* object_ =
    require fields path "object" >>= annotation_object (field path "object")
  in
  Annotation.make ~id ~subject ~predicate ~object_ |> bind_construct path

let annotation_occurrence path json =
  let* fields = object_fields path [ "annotation"; "source" ] json in
  let* annotation =
    require fields path "annotation" >>= annotation (field path "annotation")
  in
  let* source =
    require fields path "source" >>= source_location (field path "source")
  in
  Ok (Annotation_occurrence.make ~annotation ~source)

let reference_definition path json =
  let* fields = object_fields path [ "reference"; "source" ] json in
  let* reference =
    require fields path "reference" >>= reference (field path "reference")
  in
  let* source =
    require fields path "source" >>= source_location (field path "source")
  in
  Ok (Reference_definition_occurrence.make ~reference ~source)

let validate_region_range observations index region =
  match
    List.find_opt
      (fun observation ->
        Observation_id.equal (Observation.id observation)
          (Region.observation region))
      observations
  with
  | None -> Ok ()
  | Some observation -> (
      match (Region.range region, Observation.content_identity observation) with
      | None, _ -> Ok ()
      | Some range, Some identity
        when Text_range.end_ range <= Content_identity.byte_length identity ->
          Ok ()
      | Some _, None ->
          error (Printf.sprintf "$result.interpretation.regions[%d].range" index)
            "a byte range requires the owning observation to have a content identity"
      | Some _, Some _ ->
          error (Printf.sprintf "$result.interpretation.regions[%d].range" index)
            "region range exceeds the owning observation content")

let validate_region_ranges primary_observation regions =
  let* () =
    regions
    |> List.mapi (validate_region_range [ primary_observation ])
    |> List.fold_left
         (fun result validation ->
           let* () = result in
           validation)
         (Ok ())
  in
  Ok ()

let decode_interpretation ~manifest ~primary_observation path json =
  let* fields =
    object_fields path [ "interpreter"; "observation"; "regions" ] json
  in
  let* expected_interpreter =
    interpreter_of_manifest manifest |> bind_construct (field path "interpreter")
  in
  let interpreter_path = field path "interpreter" in
  let* interpreter_fields =
    require fields path "interpreter"
    >>= object_fields interpreter_path [ "name"; "version" ]
  in
  let* interpreter_name =
    require interpreter_fields interpreter_path "name"
    >>= string (field interpreter_path "name")
  in
  let* interpreter_version =
    require interpreter_fields interpreter_path "version"
    >>= string (field interpreter_path "version")
  in
  let* interpreter =
    Interpreter.make ~name:interpreter_name ~version:interpreter_version ()
    |> bind_construct interpreter_path
  in
  let* () =
    if Interpreter.equal interpreter expected_interpreter then Ok ()
    else error interpreter_path "identity must match the checked session"
  in
  let* observation_id =
    require fields path "observation"
    >>= string (field path "observation")
    >>= fun value ->
    Observation_id.make value |> bind_construct (field path "observation")
  in
  let* () =
    if Observation_id.equal observation_id (Observation.id primary_observation)
    then Ok ()
    else
      error (field path "observation")
        "identity must match the interpreted observation"
  in
  let identities =
    [
      ( Observation.id primary_observation,
        Observation.identity primary_observation );
    ]
  in
  let* regions =
    require fields path "regions"
    >>= list (field path "regions") (region ~manifest ~identities)
  in
  let* () = validate_region_ranges primary_observation regions in
  Interpretation.make ~interpreter ~observation:primary_observation ~regions
  |> Result.map_error (fun message -> "$result.interpretation: " ^ message)

let decode_failure ~operation path json =
  let* fields = object_fields path [ "code"; "message"; "data" ] json in
  let* code = require fields path "code" >>= string (field path "code") in
  let* message =
    require fields path "message" >>= string (field path "message")
  in
  let data = optional fields "data" in
  Extension_failure.make ~operation ~code ~message ?data ()
  |> bind_construct path

let decode_observe_resource_result ~manifest ~requested_origin ~content json =
  let* fields = object_fields "$result" [ "observation"; "failure" ] json in
  match optional fields "observation", optional fields "failure" with
  | Some observation, None ->
      decode_observation ~manifest ~requested_origin ~content
        "$result.observation" observation
      |> Result.map (fun observation -> Observed observation)
  | None, Some failure ->
      let* () =
        match content with
        | None -> Ok ()
        | Some _ ->
            error "$result"
              "failed Resource observation must not stream content"
      in
      decode_failure ~operation:Extension_failure.Observe_resource
        "$result.failure" failure
      |> Result.map (fun failure -> Observe_failure failure)
  | Some _, Some _ ->
      error "$result" "observation and failure are mutually exclusive"
  | None, None -> error "$result" "observation or failure is required"

let decode_interpret_result ~manifest ~primary_observation json =
  let* fields = object_fields "$result" [ "interpretation"; "failure" ] json in
  match (optional fields "interpretation", optional fields "failure") with
  | Some interpretation, None ->
      Result.map
        (fun interpretation -> Interpretation interpretation)
        (decode_interpretation ~manifest ~primary_observation
           "$result.interpretation" interpretation)
  | None, Some failure ->
      Result.map (fun failure -> Interpret_failure failure)
        (decode_failure ~operation:Extension_failure.Interpret_observation
           "$result.failure" failure)
  | Some _, Some _ ->
      error "$result" "interpretation and failure are mutually exclusive"
  | None, None -> error "$result" "interpretation or failure is required"

let decode_reference_extraction ~primary_observation path json =
  let* fields = object_fields path [ "definitions"; "uses" ] json in
  let* definitions =
    require fields path "definitions"
    >>= list (field path "definitions") reference_definition
  in
  let* uses =
    require fields path "uses"
    >>= list (field path "uses") reference_use
  in
  Reference_extraction.make ~observation:primary_observation ~definitions ~uses
  |> Result.map_error (fun message -> path ^ ": " ^ message)

let decode_annotation_extraction ~primary_observation path json =
  let* fields = object_fields path [ "occurrences" ] json in
  let* occurrences =
    require fields path "occurrences"
    >>= list (field path "occurrences") annotation_occurrence
  in
  Annotation_extraction.make ~observation:primary_observation ~occurrences
  |> Result.map_error (fun message -> path ^ ": " ^ message)

let decode_extract_references_result ~primary_observation json =
  let* fields = object_fields "$result" [ "extraction"; "failure" ] json in
  match (optional fields "extraction", optional fields "failure") with
  | Some extraction, None ->
      decode_reference_extraction ~primary_observation "$result.extraction"
        extraction
      |> Result.map (fun extraction -> Reference_extraction extraction)
  | None, Some failure ->
      decode_failure ~operation:Extension_failure.Extract_references
        "$result.failure" failure
      |> Result.map (fun failure -> Extract_references_failure failure)
  | Some _, Some _ ->
      error "$result" "extraction and failure are mutually exclusive"
  | None, None -> error "$result" "extraction or failure is required"

let decode_extract_annotations_result ~primary_observation json =
  let* fields = object_fields "$result" [ "extraction"; "failure" ] json in
  match optional fields "extraction", optional fields "failure" with
  | Some extraction, None ->
      decode_annotation_extraction ~primary_observation "$result.extraction"
        extraction
      |> Result.map (fun extraction -> Annotation_extraction extraction)
  | None, Some failure ->
      decode_failure ~operation:Extension_failure.Extract_annotations
        "$result.failure" failure
      |> Result.map (fun failure -> Extract_annotations_failure failure)
  | Some _, Some _ ->
      error "$result" "extraction and failure are mutually exclusive"
  | None, None -> error "$result" "extraction or failure is required"

let decode_resolve_result ~manifest ~target_observation ~requested_selector json =
  let* fields = object_fields "$result" [ "region"; "failure" ] json in
  match (optional fields "region", optional fields "failure") with
  | Some region_json, None ->
      let identities =
        [
          ( Observation.id target_observation,
            Observation.identity target_observation );
        ]
      in
      let* resolved =
        region ~manifest ~identities "$result.region" region_json
      in
      if Selector.compare requested_selector (Region.selector resolved) <> 0 then
        error "$result.region.selector"
          "resolved region selector must equal the requested selector"
      else
        (match (Observation.content_identity target_observation, Region.range resolved) with
        | Some content_identity, Some range
          when Text_range.end_ range > Content_identity.byte_length content_identity ->
            error "$result.region.range"
              "resolved region range exceeds the target observation"
        | Some _, (None | Some _) -> Ok (Resolved_region resolved)
        | None, None -> Ok (Resolved_region resolved)
        | None, Some _ ->
            error "$result.region.range"
              "a byte range requires a byte-backed target Observation")
  | None, Some failure ->
      Result.map (fun failure -> Resolve_failure failure)
        (decode_failure ~operation:Extension_failure.Resolve_region
           "$result.failure" failure)
  | Some _, Some _ -> error "$result" "region and failure are mutually exclusive"
  | None, None -> error "$result" "region or failure is required"

let decode_classify_result json =
  let* fields = object_fields "$result" [ "relation"; "failure" ] json in
  match (optional fields "relation", optional fields "failure") with
  | Some relation, None ->
      let* relation = string "$result.relation" relation in
      Region_extent_relation.of_string relation
      |> Result.map (fun relation -> Classified relation)
      |> Result.map_error (fun message -> "$result.relation: " ^ message)
  | None, Some failure ->
      Result.map (fun failure -> Classify_failure failure)
        (decode_failure ~operation:Extension_failure.Classify_region_extents
           "$result.failure" failure)
  | Some _, Some _ -> error "$result" "relation and failure are mutually exclusive"
  | None, None -> error "$result" "relation or failure is required"

let decode_audit_result ~policy json =
  let* fields = object_fields "$result" [ "diagnostics"; "failure" ] json in
  match optional fields "diagnostics", optional fields "failure" with
  | Some diagnostics, None ->
      let decode_diagnostic path value =
        Normal_decode.diagnostic value
        |> Result.map_error (fun message -> path ^ ": " ^ message)
      in
      let* diagnostics =
        list "$result.diagnostics" decode_diagnostic diagnostics
      in
      let invalid =
        List.find_opt
          (fun diagnostic ->
            let code = Diagnostic.code diagnostic in
            (code = Diagnostic.Sidecar_only
            && Audit_policy.sidecar_only policy = Audit_policy.Allow)
            || Diagnostic.effective_severity diagnostic
               <> Audit_policy.severity_for policy code)
          diagnostics
      in
      (match invalid with
      | None -> Ok (Audit_diagnostics (List.sort Diagnostic.compare diagnostics))
      | Some _ ->
          error "$result.diagnostics"
            "diagnostic does not conform to the requested AuditPolicy")
  | None, Some failure ->
      decode_failure ~operation:Extension_failure.Audit "$result.failure" failure
      |> Result.map (fun failure -> Audit_failure failure)
  | Some _, Some _ ->
      error "$result" "diagnostics and failure are mutually exclusive"
  | None, None -> error "$result" "diagnostics or failure is required"

let decode_derive_result json =
  let* fields = object_fields "$result" [ "patches"; "failure" ] json in
  match optional fields "patches", optional fields "failure" with
  | Some patches, None ->
      let decode_patch path value =
        Normal_decode.proposed_patch value
        |> Result.map_error (fun message -> path ^ ": " ^ message)
      in
      let* patches = list "$result.patches" decode_patch patches in
      let patches = List.sort Proposed_patch.compare patches in
      let rec has_duplicate = function
        | left :: (right :: _ as rest) ->
            Proposed_patch.compare left right = 0 || has_duplicate rest
        | [] | [ _ ] -> false
      in
      if has_duplicate patches then
        error "$result.patches" "duplicate ProposedPatch values are not allowed"
      else Ok (Derived_patches patches)
  | None, Some failure ->
      decode_failure ~operation:Extension_failure.Derive "$result.failure" failure
      |> Result.map (fun failure -> Derive_failure failure)
  | Some _, Some _ -> error "$result" "patches and failure are mutually exclusive"
  | None, None -> error "$result" "patches or failure is required"
