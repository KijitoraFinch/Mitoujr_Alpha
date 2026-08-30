let ( let* ) = Result.bind
let ( let+ ) value f = Result.map f value

let error path message = Error (path ^ ": " ^ message)

let type_name = function
  | `Assoc _ -> "object"
  | `Bool _ -> "boolean"
  | `Float _ -> "float"
  | `Int _ -> "integer"
  | `Intlit _ -> "integer literal"
  | `List _ -> "array"
  | `Null -> "null"
  | `String _ -> "string"
  | `Tuple _ -> "tuple"
  | `Variant _ -> "variant"

let field_path path name = path ^ "." ^ name
let index_path path index = path ^ "[" ^ string_of_int index ^ "]"

let duplicate_name fields =
  let names = List.map fst fields |> List.sort String.compare in
  let rec loop = function
    | left :: (right :: _ as rest) ->
        if String.equal left right then Some left else loop rest
    | _ -> None
  in
  loop names

let object_fields path allowed = function
  | `Assoc fields -> (
      match duplicate_name fields with
      | Some name -> error path ("duplicate field: " ^ name)
      | None -> (
          match
            List.find_opt
              (fun (name, _) -> not (List.mem name allowed))
              fields
          with
          | Some (name, _) -> error path ("unknown field: " ^ name)
          | None -> Ok fields))
  | json -> error path ("expected object, got " ^ type_name json)

let require fields path name =
  match List.assoc_opt name fields with
  | Some value -> Ok value
  | None -> error path ("missing field: " ^ name)

let optional fields name = List.assoc_opt name fields

let string path = function
  | `String value -> Ok value
  | json -> error path ("expected string, got " ^ type_name json)

let int path = function
  | `Int value -> Ok value
  | json -> error path ("expected integer, got " ^ type_name json)

let list path decode = function
  | `List values ->
      let rec loop index acc = function
        | [] -> Ok (List.rev acc)
        | value :: rest ->
            let* decoded = decode (index_path path index) value in
            loop (index + 1) (decoded :: acc) rest
      in
      loop 0 [] values
  | json -> error path ("expected array, got " ^ type_name json)

let bind_construct path = function
  | Ok value -> Ok value
  | Error message -> error path message

let workspace_path_at path json =
  let* value = string path json in
  Workspace_path.of_canonical_string value |> bind_construct path

let content_identity_at path json =
  let* fields = object_fields path [ "hash"; "size" ] json in
  let* hash = require fields path "hash" in
  let* hash = string (field_path path "hash") hash in
  let* size = require fields path "size" in
  let* size = int (field_path path "size") size in
  if size < 0 then
    error (field_path path "size") "byte length must not be negative"
  else
    Content_identity.of_display_hash ~hash ~byte_length:size
    |> bind_construct (field_path path "hash")

let text_range_at path json =
  let* fields = object_fields path [ "start"; "end" ] json in
  let* start = require fields path "start" in
  let* start = int (field_path path "start") start in
  let* end_ = require fields path "end" in
  let* end_ = int (field_path path "end") end_ in
  Text_range.make ~start ~end_ |> bind_construct path

let text_edit_at path json =
  let* fields = object_fields path [ "range"; "replacement" ] json in
  let* range = require fields path "range" in
  let* range = text_range_at (field_path path "range") range in
  let* replacement = require fields path "replacement" in
  let* replacement = string (field_path path "replacement") replacement in
  Text_edit.make ~range ~replacement |> bind_construct path

let provenance_at path json =
  let* fields = object_fields path [ "source"; "detail" ] json in
  let* source = require fields path "source" in
  let* source = string (field_path path "source") source in
  let* detail =
    match optional fields "detail" with
    | None -> Ok None
    | Some value ->
        let+ detail = string (field_path path "detail") value in
        Some detail
  in
  Provenance.make ~source ?detail () |> bind_construct path

let origin_at path json =
  let* fields =
    object_fields path
      [ "kind"; "path"; "repo"; "rev"; "url"; "name"; "uri"; "observer"; "locator" ]
      json
  in
  let* kind = require fields path "kind" in
  let* kind = string (field_path path "kind") kind in
  match kind with
  | "workspace" ->
      let* value = require fields path "path" in
      let* value = workspace_path_at (field_path path "path") value in
      if List.length fields <> 2 then error path "workspace Origin has invalid fields"
      else Ok (Origin.workspace value)
  | "git" ->
      let* repo = require fields path "repo" in
      let* repo = string (field_path path "repo") repo in
      let* git_path = require fields path "path" in
      let* git_path = string (field_path path "path") git_path in
      let* rev =
        match optional fields "rev" with
        | None -> Ok None
        | Some value ->
            let+ value = string (field_path path "rev") value in
            Some value
      in
      let expected_fields = if Option.is_some rev then 4 else 3 in
      if List.length fields <> expected_fields then
        error path "git Origin has invalid fields"
      else Origin.git ~repo ?rev ~path:git_path () |> bind_construct path
  | "web" ->
      let* value = require fields path "url" in
      let* value = string (field_path path "url") value in
      if List.length fields <> 2 then error path "web Origin has invalid fields"
      else Origin.web value |> bind_construct path
  | "generated" ->
      let* value = require fields path "name" in
      let* value = string (field_path path "name") value in
      if List.length fields <> 2 then error path "generated Origin has invalid fields"
      else Origin.generated value |> bind_construct path
  | "external" ->
      let* value = require fields path "uri" in
      let* value = string (field_path path "uri") value in
      if List.length fields <> 2 then error path "external Origin has invalid fields"
      else Origin.external_ value |> bind_construct path
  | "extension" ->
      let* observer = require fields path "observer" in
      let observer_path = field_path path "observer" in
      let* observer_fields =
        object_fields observer_path [ "name"; "version" ] observer
      in
      let* name = require observer_fields observer_path "name" in
      let* name = string (field_path observer_path "name") name in
      let* version = require observer_fields observer_path "version" in
      let* version = string (field_path observer_path "version") version in
      if List.length observer_fields <> 2 || List.length fields <> 3 then
        error path "extension Origin has invalid fields"
      else
        let* observer =
          Resource_observer.make ~name ~version () |> bind_construct observer_path
        in
        let* locator = require fields path "locator" in
        Origin.extension ~observer ~locator () |> bind_construct path
  | _ -> error (field_path path "kind") "unsupported Origin kind"

let scoped_region_id_at path json =
  let* fields = object_fields path [ "observation"; "local" ] json in
  let* observation = require fields path "observation" in
  let* observation = string (field_path path "observation") observation in
  let* observation =
    Observation_id.make observation
    |> bind_construct (field_path path "observation")
  in
  let* local = require fields path "local" in
  let* local = string (field_path path "local") local in
  if List.length fields <> 2 then error path "scoped Region ID has invalid fields"
  else Region_id.make ~observation ~local |> bind_construct path

let annotation_id_at path json =
  let* fields = object_fields path [ "scope"; "local" ] json in
  let* scope = require fields path "scope" in
  let* scope = origin_at (field_path path "scope") scope in
  let* local = require fields path "local" in
  let* local = string (field_path path "local") local in
  if List.length fields <> 2 then error path "AnnotationId has invalid fields"
  else Annotation_id.make ~scope ~local |> bind_construct path

let diagnostic_location_at path json =
  let* fields =
    object_fields path [ "observation"; "region"; "annotation"; "range" ] json
  in
  let* observation =
    match optional fields "observation" with
    | None -> Ok None
    | Some value ->
        let* value = string (field_path path "observation") value in
        let+ value =
          Observation_id.make value
          |> bind_construct (field_path path "observation")
        in
        Some value
  in
  let* region =
    match optional fields "region" with
    | None -> Ok None
    | Some value ->
        let+ value = scoped_region_id_at (field_path path "region") value in
        Some value
  in
  let* annotation =
    match optional fields "annotation" with
    | None -> Ok None
    | Some value ->
        let+ value = annotation_id_at (field_path path "annotation") value in
        Some value
  in
  let* range =
    match optional fields "range" with
    | None -> Ok None
    | Some value ->
        let+ value = text_range_at (field_path path "range") value in
        Some value
  in
  Ok Diagnostic.{ observation; region; annotation; range }

let extension_operation path = function
  | "session" -> Ok Extension_failure.Session
  | "observe-resource" -> Ok Extension_failure.Observe_resource
  | "interpret-observation" -> Ok Extension_failure.Interpret_observation
  | "extract-annotations" -> Ok Extension_failure.Extract_annotations
  | "extract-references" -> Ok Extension_failure.Extract_references
  | "resolve-region" -> Ok Extension_failure.Resolve_region
  | "classify-region-extents" -> Ok Extension_failure.Classify_region_extents
  | "audit" -> Ok Extension_failure.Audit
  | "derive" -> Ok Extension_failure.Derive
  | _ -> error path "unsupported extension operation"

let extension_failure_at path ~message json =
  let* fields = object_fields path [ "operation"; "code"; "data" ] json in
  let* operation = require fields path "operation" in
  let* operation = string (field_path path "operation") operation in
  let* operation = extension_operation (field_path path "operation") operation in
  let* code = require fields path "code" in
  let* code = string (field_path path "code") code in
  let data = optional fields "data" in
  Extension_failure.make ~operation ~code ~message ?data ()
  |> bind_construct path

let diagnostic_at ~decode_patch path json =
  let* fields =
    object_fields path
      [
        "code";
        "defaultSeverity";
        "effectiveSeverity";
        "message";
        "location";
        "extensionFailure";
        "suggestedFixes";
      ]
      json
  in
  let* code = require fields path "code" in
  let* code = string (field_path path "code") code in
  let* code =
    Diagnostic.code_of_string code |> bind_construct (field_path path "code")
  in
  let* default_severity = require fields path "defaultSeverity" in
  let* default_severity =
    string (field_path path "defaultSeverity") default_severity
  in
  let expected_default =
    Diagnostic.default_severity code |> Diagnostic.severity_string
  in
  let* () =
    if String.equal default_severity expected_default then Ok ()
    else error (field_path path "defaultSeverity") "does not match diagnostic code"
  in
  let* effective_severity = require fields path "effectiveSeverity" in
  let* effective_severity =
    string (field_path path "effectiveSeverity") effective_severity
  in
  let* effective_severity =
    Diagnostic.severity_of_string effective_severity
    |> bind_construct (field_path path "effectiveSeverity")
  in
  let* message = require fields path "message" in
  let* message = string (field_path path "message") message in
  let* location =
    match optional fields "location" with
    | None -> Ok None
    | Some value ->
        let+ value = diagnostic_location_at (field_path path "location") value in
        Some value
  in
  let* extension_failure =
    match optional fields "extensionFailure" with
    | None -> Ok None
    | Some value ->
        let+ value =
          extension_failure_at (field_path path "extensionFailure") ~message value
        in
        Some value
  in
  let* suggested_fixes = require fields path "suggestedFixes" in
  let* suggested_fixes =
    list (field_path path "suggestedFixes") decode_patch suggested_fixes
  in
  Diagnostic.make ~code ~effective_severity ~message ?location
    ?extension_failure ~suggested_fixes ()
  |> bind_construct path

let proposed_patch_at path json =
  let* fields =
    object_fields path
      [
        "id";
        "target";
        "operation";
        "expectedContentIdentity";
        "resultingContentIdentity";
        "edits";
        "content";
        "reason";
        "provenance";
      ]
      json
  in
  let* id = require fields path "id" in
  let* id = string (field_path path "id") id in
  let* id = Patch_id.make id |> bind_construct (field_path path "id") in
  let* target = require fields path "target" in
  let* target = workspace_path_at (field_path path "target") target in
  let* operation = require fields path "operation" in
  let* operation = string (field_path path "operation") operation in
  let* resulting_identity = require fields path "resultingContentIdentity" in
  let* resulting_identity =
    content_identity_at
      (field_path path "resultingContentIdentity")
      resulting_identity
  in
  let* reason = require fields path "reason" in
  let* reason = string (field_path path "reason") reason in
  let* provenance = require fields path "provenance" in
  let* provenance = provenance_at (field_path path "provenance") provenance in
  match operation with
  | "create" ->
      if optional fields "expectedContentIdentity" <> None then
        error path "create patch must not contain expectedContentIdentity"
      else if optional fields "edits" <> None then
        error path "create patch must not contain edits"
      else
        let* content = require fields path "content" in
        let* content = string (field_path path "content") content in
        Proposed_patch.make_create ~id ~target ~resulting_identity ~content
          ~reason ~provenance
        |> bind_construct path
  | "edit" ->
      if optional fields "content" <> None then
        error path "edit patch must not contain content"
      else
        let* expected_identity =
          require fields path "expectedContentIdentity"
        in
        let* expected_identity =
          content_identity_at (field_path path "expectedContentIdentity")
            expected_identity
        in
        let* edits = require fields path "edits" in
        let* edits = list (field_path path "edits") text_edit_at edits in
        Proposed_patch.make ~id ~target ~expected_identity ~resulting_identity
          ~edits ~reason ~provenance
        |> bind_construct path
  | _ -> error (field_path path "operation") "unsupported patch operation"

let workspace_path json = workspace_path_at "$" json
let content_identity json = content_identity_at "$" json
let text_range json = text_range_at "$" json
let text_edit json = text_edit_at "$" json
let provenance json = provenance_at "$" json
let proposed_patch json = proposed_patch_at "$" json
let diagnostic json = diagnostic_at ~decode_patch:proposed_patch_at "$" json
