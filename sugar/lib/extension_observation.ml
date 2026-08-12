type observation_result = {
  artifacts : Artifact.t list;
  regions : Region.t list;
  references : Reference.t list;
  annotations : Annotation.t list;
}

type remote_failure = {
  code : string;
  message : string;
  data : Yojson.Safe.t option;
}

type observe_result =
  | Observation of observation_result
  | Failure of remote_failure

type resolve_result =
  | Resolved_region of Region.t
  | Resolve_failure of remote_failure

let ( let* ) = Result.bind
let ( >>= ) = Result.bind

let base64_alphabet =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

let base64_encode content =
  let length = String.length content in
  let output_length = ((length + 2) / 3) * 4 in
  let output = Bytes.create output_length in
  let byte index = Char.code (String.get content index) in
  let set index value =
    Bytes.set output index (String.get base64_alphabet value)
  in
  let rec loop input output_index =
    if input >= length then ()
    else
      let first = byte input in
      let second = if input + 1 < length then byte (input + 1) else 0 in
      let third = if input + 2 < length then byte (input + 2) else 0 in
      set output_index (first lsr 2);
      set (output_index + 1) (((first land 0x03) lsl 4) lor (second lsr 4));
      if input + 1 < length then
        set (output_index + 2)
          (((second land 0x0f) lsl 2) lor (third lsr 6))
      else Bytes.set output (output_index + 2) '=';
      if input + 2 < length then set (output_index + 3) (third land 0x3f)
      else Bytes.set output (output_index + 3) '=';
      loop (input + 3) (output_index + 4)
  in
  loop 0 0;
  Bytes.unsafe_to_string output

let content_json content =
  if Utf8.is_valid content then
    `Assoc [ ("kind", `String "inlineText"); ("text", `String content) ]
  else
    `Assoc
      [
        ("kind", `String "inlineBase64");
        ("base64", `String (base64_encode content));
      ]

let observe_params ~artifact ~content =
  let artifact_json =
    artifact |> Normal.Artifact.normalize |> Normal_json.artifact
  in
  `Assoc [ ("artifact", artifact_json); ("content", content_json content) ]

let resolve_params ~artifact ~content ~selector =
  let artifact_json =
    artifact |> Normal.Artifact.normalize |> Normal_json.artifact
  in
  let selector_json =
    selector |> Normal.Selector.normalize |> Normal_json.selector
  in
  `Assoc
    [
      ("artifact", artifact_json);
      ("content", content_json content);
      ("selector", selector_json);
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
  let* fields = object_fields path [ "artifact"; "local" ] json in
  let* artifact = require fields path "artifact" in
  let* artifact = string (field path "artifact") artifact in
  let* artifact = Artifact_id.make artifact |> bind_construct (field path "artifact") in
  let* local = require fields path "local" in
  let* local = string (field path "local") local in
  make ~artifact ~local |> bind_construct path

let region_id path json = scoped_id path Region_id.make json
let reference_id path json = scoped_id path Reference_id.make json
let annotation_id path json = scoped_id path Annotation_id.make json

let content_identity path json =
  Normal_decode.content_identity json
  |> Result.map_error (fun message -> path ^ ": " ^ message)

let range path json =
  Normal_decode.text_range json |> Result.map_error (fun message -> path ^ ": " ^ message)

let workspace_path path json =
  Normal_decode.workspace_path json
  |> Result.map_error (fun message -> path ^ ": " ^ message)

let origin path json =
  let* fields =
    object_fields path
      [ "kind"; "path"; "repo"; "rev"; "url"; "name"; "uri"; "provider"; "locator" ]
      json
  in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  match kind with
  | "workspace" ->
      let* () = require_only path fields [ "kind"; "path" ] in
      let* value = require fields path "path" >>= workspace_path (field path "path") in
      Ok (Artifact.workspace value)
  | "git" ->
      let* () = require_only path fields [ "kind"; "repo"; "rev"; "path" ] in
      let* repo = require fields path "repo" >>= string (field path "repo") in
      let* path_value = require fields path "path" >>= string (field path "path") in
      let* rev =
        match optional fields "rev" with
        | None -> Ok None
        | Some value -> Result.map Option.some (string (field path "rev") value)
      in
      Artifact.git ~repo ?rev ~path:path_value () |> bind_construct path
  | "web" ->
      let* () = require_only path fields [ "kind"; "url" ] in
      let* url = require fields path "url" >>= string (field path "url") in
      Artifact.web url |> bind_construct path
  | "generated" ->
      let* () = require_only path fields [ "kind"; "name" ] in
      let* name = require fields path "name" >>= string (field path "name") in
      Artifact.generated name |> bind_construct path
  | "external" ->
      let* () = require_only path fields [ "kind"; "uri" ] in
      let* uri = require fields path "uri" >>= string (field path "uri") in
      Artifact.external_ uri |> bind_construct path
  | "extension" ->
      let* () = require_only path fields [ "kind"; "provider"; "locator" ] in
      let* provider =
        require fields path "provider" >>= string (field path "provider")
      in
      let* locator =
        require fields path "locator" >>= string (field path "locator")
      in
      Artifact.extension ~provider ~locator () |> bind_construct path
  | _ -> error (field path "kind") "unsupported origin kind"

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
  | "whole-artifact" ->
      let* () = require_only path fields [ "kind" ] in
      Ok Selector.Whole_artifact
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

let provenance path json =
  let* fields = object_fields path [ "source"; "detail" ] json in
  let* source = require fields path "source" >>= string (field path "source") in
  let* detail =
    match optional fields "detail" with
    | None -> Ok None
    | Some value -> Result.map Option.some (string (field path "detail") value)
  in
  Provenance.make ~source ?detail () |> bind_construct path

let artifact path json =
  let* fields = object_fields path [ "id"; "origin"; "mediaType"; "contentIdentity" ] json in
  let* id = require fields path "id" >>= string (field path "id") in
  let* id = Artifact_id.make id |> bind_construct (field path "id") in
  let* origin = require fields path "origin" >>= origin (field path "origin") in
  let* media_type =
    match optional fields "mediaType" with
    | None -> Ok None
    | Some value -> Result.map Option.some (string (field path "mediaType") value)
  in
  let* content_identity =
    require fields path "contentIdentity" >>= content_identity (field path "contentIdentity")
  in
  Artifact.make ~id ~origin ?media_type ~content_identity () |> bind_construct path

let interpreter_of_descriptor descriptor =
  let capability = Extension_descriptor.capability descriptor in
  Interpreter.make ~name:(Capability.name capability)
    ~version:(Capability.version capability) ()
  |> Result.get_ok

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

let region ~descriptor ~identities path json =
  let* fields =
    object_fields path
      [ "id"; "selector"; "interpreter"; "interpreterVersion"; "summary"; "range"; "fingerprint" ]
      json
  in
  let* id = require fields path "id" >>= region_id (field path "id") in
  let artifact_id = Region_id.artifact id in
  let* observation_identity =
    match
      List.find_opt
        (fun (candidate, _) -> Artifact_id.equal candidate artifact_id)
        identities
    with
    | Some (_, identity) -> Ok identity
    | None -> error (field path "id") "region artifact is not present in observation artifacts"
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
  | Selector.Whole_artifact ->
      if optional fields "interpreter" <> None || optional fields "interpreterVersion" <> None then
        error path "whole-artifact region must not specify an interpreter"
      else Ok (Region.whole ~id ~observation_identity)
  | _ ->
      let descriptor_interpreter = interpreter_of_descriptor descriptor in
      let* interpreter =
        match optional_interpreter path fields with
        | Error _ as error -> error
        | Ok None -> Ok descriptor_interpreter
        | Ok (Some explicit) ->
            if Interpreter.equal explicit descriptor_interpreter then Ok explicit
            else error path "region interpreter must match the extension descriptor"
      in
      Region.make ~id ~observation_identity ~selector ~interpreter ?summary
        ?range ?fingerprint ()
      |> bind_construct path

let region_address path json =
  let* fields =
    object_fields path
      [ "artifact"; "selector"; "interpreter"; "interpreterVersion" ] json
  in
  let* artifact = require fields path "artifact" >>= origin (field path "artifact") in
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
  Region_address.make ~artifact ~selector ?interpreter ?interpreter_version ()
  |> bind_construct path

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
    object_fields path [ "id"; "target"; "binding"; "expectations"; "provenance" ] json
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
  let* provenance =
    require fields path "provenance" >>= list (field path "provenance") provenance
  in
  Ok (Reference.make ~id ~target ~binding ~expectations ~provenance ())

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
  | _ -> error (field path "kind") "unsupported region ref kind"

let annotation_object path json =
  let* fields = object_fields path [ "kind"; "region"; "reference"; "value" ] json in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  match kind with
  | "region" ->
      let* () = require_only path fields [ "kind"; "region" ] in
      let* region = require fields path "region" >>= region_ref (field path "region") in
      Ok (Annotation.Region_object region)
  | "reference" ->
      let* () = require_only path fields [ "kind"; "reference" ] in
      let* reference =
        require fields path "reference" >>= reference_id (field path "reference")
      in
      Ok (Annotation.Reference_object reference)
  | "literal" ->
      let* () = require_only path fields [ "kind"; "value" ] in
      let* value = require fields path "value" >>= string (field path "value") in
      Ok (Annotation.Literal value)
  | _ -> error (field path "kind") "unsupported annotation object kind"

let materialization path json =
  let* fields = object_fields path [ "kind"; "artifact"; "range"; "path" ] json in
  let* kind = require fields path "kind" >>= string (field path "kind") in
  let artifact_field () =
    let* artifact = require fields path "artifact" >>= string (field path "artifact") in
    Artifact_id.make artifact |> bind_construct (field path "artifact")
  in
  match kind with
  | "markdown-inline" ->
      let* () = require_only path fields [ "kind"; "artifact"; "range" ] in
      let* artifact = artifact_field () in
      let* range = require fields path "range" >>= range (field path "range") in
      Ok (Annotation.Markdown_inline { artifact; range })
  | "source-comment" ->
      let* () = require_only path fields [ "kind"; "artifact"; "range" ] in
      let* artifact = artifact_field () in
      let* range = require fields path "range" >>= range (field path "range") in
      Ok (Annotation.Source_comment { artifact; range })
  | "sidecar" ->
      let* () = require_only path fields [ "kind"; "artifact"; "path" ] in
      let* artifact = artifact_field () in
      let* path_value =
        match optional fields "path" with
        | None -> Ok None
        | Some value -> Result.map Option.some (workspace_path (field path "path") value)
      in
      Ok (Annotation.Sidecar { artifact; path = path_value })
  | "generated-index" ->
      let* () = require_only path fields [ "kind"; "artifact" ] in
      let* artifact = artifact_field () in
      Ok (Annotation.Generated_index { artifact })
  | _ -> error (field path "kind") "unsupported materialization kind"

let annotation path json =
  let* fields =
    object_fields path
      [ "id"; "subject"; "predicate"; "object"; "provenance"; "materialization" ]
      json
  in
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
  let* provenance =
    require fields path "provenance" >>= list (field path "provenance") provenance
  in
  let* materialization =
    require fields path "materialization"
    >>= list (field path "materialization") materialization
  in
  Annotation.make ~id ~subject:(Annotation.Region subject) ~predicate ~object_
    ~provenance ~materialization
  |> bind_construct path

let decode_observation ~descriptor ~primary_artifact path json =
  let* fields =
    object_fields path [ "artifacts"; "regions"; "references"; "annotations" ] json
  in
  let* artifacts =
    require fields path "artifacts" >>= list (field path "artifacts") artifact
  in
  let all_artifacts = primary_artifact :: artifacts in
  let identities =
    List.map
      (fun artifact -> (Artifact.id artifact, Artifact.observation_identity artifact))
      all_artifacts
  in
  let* regions =
    require fields path "regions"
    >>= list (field path "regions") (region ~descriptor ~identities)
  in
  let* references =
    require fields path "references"
    >>= list (field path "references") reference
  in
  let* annotations =
    require fields path "annotations"
    >>= list (field path "annotations") annotation
  in
  Ok { artifacts; regions; references; annotations }

let decode_failure path json =
  let* fields = object_fields path [ "code"; "message"; "data" ] json in
  let* code = require fields path "code" >>= string (field path "code") in
  let* message =
    require fields path "message" >>= string (field path "message")
  in
  let data = optional fields "data" in
  if String.length code = 0 then error (field path "code") "must not be empty"
  else if String.length message = 0 then
    error (field path "message") "must not be empty"
  else Ok { code; message; data }

let decode_observe_result ~descriptor ~primary_artifact json =
  let* fields = object_fields "$result" [ "observation"; "failure" ] json in
  match (optional fields "observation", optional fields "failure") with
  | Some observation, None ->
      Result.map
        (fun observation -> Observation observation)
        (decode_observation ~descriptor ~primary_artifact "$result.observation"
           observation)
  | None, Some failure ->
      Result.map (fun failure -> Failure failure)
        (decode_failure "$result.failure" failure)
  | Some _, Some _ -> error "$result" "observation and failure are mutually exclusive"
  | None, None -> error "$result" "observation or failure is required"

let decode_resolve_result ~descriptor ~target_artifact ~requested_selector json =
  let* fields = object_fields "$result" [ "region"; "failure" ] json in
  match (optional fields "region", optional fields "failure") with
  | Some region_json, None ->
      let identities =
        [
          ( Artifact.id target_artifact,
            Artifact.observation_identity target_artifact );
        ]
      in
      let* resolved =
        region ~descriptor ~identities "$result.region" region_json
      in
      if Selector.compare requested_selector (Region.selector resolved) <> 0 then
        error "$result.region.selector"
          "resolved region selector must equal the requested selector"
      else
        let content_length =
          Artifact.content_identity target_artifact
          |> Content_identity.byte_length
        in
        (match Region.range resolved with
        | Some range when Text_range.end_ range > content_length ->
            error "$result.region.range"
              "resolved region range exceeds the target observation"
        | None | Some _ -> Ok (Resolved_region resolved))
  | None, Some failure ->
      Result.map (fun failure -> Resolve_failure failure)
        (decode_failure "$result.failure" failure)
  | Some _, Some _ -> error "$result" "region and failure are mutually exclusive"
  | None, None -> error "$result" "region or failure is required"
