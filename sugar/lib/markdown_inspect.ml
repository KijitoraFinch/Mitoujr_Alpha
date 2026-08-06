type t = {
  regions : Region.t list;
  references : Reference.t list;
  occurrences : Reference_occurrence.t list;
  annotations : Annotation.t list;
}

module Reference_map = Map.Make (Reference_id)

let markdown_type =
  Observation_type.make ~name:"text/markdown" ~version:"1" ()
  |> Result.get_ok

let markdown_interpreter =
  Interpreter.make ~name:"markdown" ~version:"1" () |> Result.get_ok

type block =
  | Html of { range : Text_range.t; source : string }
  | Paragraph of {
      range : Text_range.t;
      summary : string;
    }

type marker =
  | Region_marker of { local : string; range : Text_range.t }
  | Annotation_marker of {
      local : string;
      predicate : string;
      reference : string;
      range : Text_range.t;
    }

type link = {
  destination : string;
  range : Text_range.t;
}

let ( let* ) = Result.bind

let range_of_meta meta =
  let location = Cmarkit.Meta.textloc meta in
  if Cmarkit.Textloc.is_none location || Cmarkit.Textloc.is_empty location then
    Error "CommonMark node has no source range"
  else
    Text_range.make ~start:(Cmarkit.Textloc.first_byte location)
      ~end_:(Cmarkit.Textloc.last_byte location + 1)

let source_range content range =
  let start = Text_range.start range in
  let length = Text_range.length range in
  if start < 0 || length < 0 || start > String.length content - length then
    Error "CommonMark source range is outside the document"
  else Ok (String.sub content start length)

let trim = String.trim

let parse_attributes path tokens =
  let rec loop names values = function
    | [] -> Ok (List.rev values)
    | token :: rest -> (
        match String.index_opt token '=' with
        | None -> Error (path ^ ": expected key=value attribute")
        | Some index ->
            let name = String.sub token 0 index in
            let value =
              String.sub token (index + 1) (String.length token - index - 1)
            in
            if String.length name = 0 || String.length value = 0 then
              Error (path ^ ": attribute name and value must not be empty")
            else if List.mem name names then
              Error (path ^ ": duplicate attribute " ^ name)
            else loop (name :: names) ((name, value) :: values) rest)
  in
  loop [] [] tokens

let require_exact_attributes path required attributes =
  match
    List.find_opt (fun (name, _) -> not (List.mem name required)) attributes
  with
  | Some (name, _) -> Error (path ^ ": unknown attribute " ^ name)
  | None ->
      let rec require = function
        | [] -> Ok ()
        | name :: rest ->
            if List.mem_assoc name attributes then require rest
            else Error (path ^ ": missing attribute " ^ name)
      in
      let* () = require required in
      Ok attributes

let parse_marker range source =
  let source = trim source in
  let length = String.length source in
  if length < 7 || String.sub source 0 4 <> "<!--"
     || String.sub source (length - 3) 3 <> "-->"
  then Ok None
  else
    let body = String.sub source 4 (length - 7) |> trim in
    if String.length body < 7 || String.sub body 0 7 <> "monika:" then Ok None
    else
      let tokens =
        String.split_on_char ' ' body |> List.filter (fun value -> value <> "")
      in
      match tokens with
      | [] -> Error "Markdown comment: empty Monika directive"
      | directive :: attributes ->
          let* attributes = parse_attributes "Markdown comment" attributes in
          (match directive with
          | "monika:region" ->
              let* attributes =
                require_exact_attributes "monika:region" [ "id" ] attributes
              in
              Ok
                (Some
                   (Region_marker
                      { local = List.assoc "id" attributes; range }))
          | "monika:annotation" ->
              let* attributes =
                require_exact_attributes "monika:annotation"
                  [ "id"; "predicate"; "ref" ] attributes
              in
              Ok
                (Some
                   (Annotation_marker
                      {
                        local = List.assoc "id" attributes;
                        predicate = List.assoc "predicate" attributes;
                        reference = List.assoc "ref" attributes;
                        range;
                      }))
          | unknown -> Error ("unknown Monika directive: " ^ unknown))

let blocks content document =
  let block _folder acc = function
    | Cmarkit.Block.Html_block (_, meta) -> (
        match range_of_meta meta with
        | Error _ -> Cmarkit.Folder.ret acc
        | Ok range -> (
            match source_range content range with
            | Error _ -> Cmarkit.Folder.ret acc
            | Ok source -> Cmarkit.Folder.ret (Html { range; source } :: acc)))
    | Cmarkit.Block.Paragraph (paragraph, meta) -> (
        match range_of_meta meta with
        | Error _ -> Cmarkit.Folder.ret acc
        | Ok range ->
            let summary =
              Cmarkit.Block.Paragraph.inline paragraph
              |> Cmarkit.Inline.to_plain_text ~break_on_soft:false
              |> List.map (String.concat "") |> String.concat "\n"
            in
            Cmarkit.Folder.ret (Paragraph { range; summary } :: acc))
    | _ -> Cmarkit.Folder.default
  in
  Cmarkit.Folder.fold_doc (Cmarkit.Folder.make ~block ()) [] document
  |> List.sort (fun left right ->
         let start = function
           | Html { range; _ } | Paragraph { range; _ } -> Text_range.start range
         in
         Int.compare (start left) (start right))

let links document =
  let definitions = Cmarkit.Doc.defs document in
  let inline _folder acc = function
    | Cmarkit.Inline.Link (link, meta) -> (
        match
          ( Cmarkit.Inline.Link.reference_definition definitions link,
            range_of_meta meta )
        with
        | Some (Cmarkit.Link_definition.Def (definition, _)), Ok range -> (
            match Cmarkit.Link_definition.dest definition with
            | Some (destination, _) ->
                Cmarkit.Folder.ret ({ destination; range } :: acc)
            | None -> Cmarkit.Folder.ret acc)
        | _ -> Cmarkit.Folder.ret acc)
    | _ -> Cmarkit.Folder.default
  in
  Cmarkit.Folder.fold_doc (Cmarkit.Folder.make ~inline ()) [] document
  |> List.rev

let markers blocks =
  List.fold_left
    (fun result -> function
      | Paragraph _ -> result
      | Html { range; source } ->
          let* acc = result in
          let* marker = parse_marker range source in
          Ok (match marker with None -> acc | Some marker -> marker :: acc))
    (Ok []) blocks
  |> Result.map List.rev

let next_paragraph blocks marker_range =
  let rec loop = function
    | [] -> Ok None
    | Paragraph { range; summary } :: _
      when Text_range.start range >= Text_range.end_ marker_range ->
        Ok (Some (range, summary))
    | Html { range; source } :: rest
      when Text_range.start range >= Text_range.end_ marker_range ->
        let* marker = parse_marker range source in
        (match marker with
        | Some _ -> Error "monika:region must be followed by a paragraph before another directive"
        | None -> loop rest)
    | _ :: rest -> loop rest
  in
  loop blocks

let region_from_marker ~artifact ~observation_identity ~content blocks = function
  | Annotation_marker _ -> Ok None
  | Region_marker { local; range = marker_range } -> (
      let* paragraph = next_paragraph blocks marker_range in
      match paragraph with
      | None -> Error ("monika:region " ^ local ^ " has no following paragraph")
      | Some (range, summary) ->
          let* id = Region_id.make ~artifact ~local in
          let selector = Selector.Text_range range in
          let* region_content = source_range content range in
          let fingerprint = Content_digest.of_content region_content |> Content_digest.to_string in
          Region.make ~id ~observation_identity ~selector
            ~interpreter:markdown_interpreter ~summary ~range ~fingerprint ()
          |> Result.map Option.some)

let preceding_region regions range =
  List.fold_left
    (fun best region ->
      match Region.range region with
      | None -> best
      | Some region_range
        when Text_range.end_ region_range <= Text_range.start range -> (
          match best with
          | None -> Some region
          | Some previous -> (
              match Region.range previous with
              | Some previous_range
                when Text_range.end_ previous_range
                     >= Text_range.end_ region_range ->
                  best
              | _ -> Some region))
      | Some _ -> best)
    None regions

let percent_decode path value =
  let hex = function
    | '0' .. '9' as char -> Some (Char.code char - Char.code '0')
    | 'a' .. 'f' as char -> Some (10 + Char.code char - Char.code 'a')
    | 'A' .. 'F' as char -> Some (10 + Char.code char - Char.code 'A')
    | _ -> None
  in
  let buffer = Buffer.create (String.length value) in
  let rec loop index =
    if index = String.length value then
      let decoded = Buffer.contents buffer in
      if Utf8.is_valid decoded then Ok decoded else Error (path ^ ": invalid UTF-8")
    else if value.[index] <> '%' then (
      Buffer.add_char buffer value.[index];
      loop (index + 1))
    else if index + 2 >= String.length value then Error (path ^ ": truncated percent escape")
    else
      match (hex value.[index + 1], hex value.[index + 2]) with
      | Some high, Some low ->
          Buffer.add_char buffer (Char.chr ((high lsl 4) lor low));
          loop (index + 3)
      | _ -> Error (path ^ ": invalid percent escape")
  in
  loop 0

type parsed_link =
  | Named_reference of Workspace_path.t * Identifier.t
  | Direct_target of Region_address.t

let has_uri_scheme value =
  let valid_initial = function
    | 'a' .. 'z' | 'A' .. 'Z' -> true
    | _ -> false
  in
  let valid_rest = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '+' | '-' | '.' -> true
    | _ -> false
  in
  match String.index_opt value ':' with
  | None | Some 0 -> false
  | Some separator ->
      valid_initial value.[0]
      &&
      let rec loop index =
        index = separator || (valid_rest value.[index] && loop (index + 1))
      in
      loop 1

let workspace_link_path primary_path raw_path =
  let* target_path = percent_decode "Markdown link path" raw_path in
  if String.length target_path = 0 then Ok primary_path
  else
    let base =
      Workspace_path.segments primary_path |> List.rev |> List.tl |> List.rev
    in
    let combined = String.concat "/" (base @ [ target_path ]) in
    Workspace_path.of_native_string ~flavor:Workspace_path.Posix combined

let direct_address origin =
  Region_address.make ~artifact:origin ~selector:Selector.Whole_artifact ()

let parse_link_target primary_path destination =
  if has_uri_scheme destination then
    let origin =
      if
        String.starts_with ~prefix:"http://" destination
        || String.starts_with ~prefix:"https://" destination
      then Artifact.web destination
      else Artifact.external_ destination
    in
    let* origin = origin in
    let* address = direct_address origin in
    Ok (Direct_target address)
  else if String.contains destination '?' then
    Error "workspace Markdown link query is not supported"
  else
    match String.index_opt destination '#' with
    | None ->
        let* path = workspace_link_path primary_path destination in
        let* address = direct_address (Artifact.workspace path) in
        Ok (Direct_target address)
    | Some separator ->
        let raw_path = String.sub destination 0 separator in
        let raw_fragment =
          String.sub destination (separator + 1)
            (String.length destination - separator - 1)
        in
        if String.contains raw_fragment '#' then
          Error "Markdown link has multiple fragments"
        else if String.length raw_fragment = 0 then
          let* path = workspace_link_path primary_path raw_path in
          let* address = direct_address (Artifact.workspace path) in
          Ok (Direct_target address)
        else
          let* path = workspace_link_path primary_path raw_path in
          let* fragment =
            percent_decode "Markdown link fragment" raw_fragment
          in
          let* id = Identifier.make fragment in
          Ok (Named_reference (path, id))

let reference_of_link ~artifact ~path link =
  let* target = parse_link_target path link.destination in
  match target with
  | Direct_target _ -> Ok None
  | Named_reference (target_path, fragment) ->
      let local = Identifier.to_string fragment in
      let* id = Reference_id.make ~artifact ~local in
      let* target =
        Region_address.make ~artifact:(Artifact.workspace target_path)
          ~selector:(Selector.Region_id fragment) ()
      in
      let* provenance =
        Provenance.make ~source:"markdown-inline"
          ~detail:
            (Printf.sprintf "%d:%d" (Text_range.start link.range)
               (Text_range.end_ link.range))
          ()
      in
      Ok
        (Some
           (Reference.make ~id ~target ~binding:Reference.Tracking
              ~provenance:[ provenance ] ()))

let containing_region regions range =
  let candidates =
    List.filter
      (fun region ->
        match Region.range region with
        | Some candidate ->
            Text_range.start candidate <= Text_range.start range
            && Text_range.end_ range <= Text_range.end_ candidate
        | None -> false)
      regions
    |> List.sort (fun left right ->
           match (Region.range left, Region.range right) with
           | Some left, Some right ->
               Int.compare (Text_range.length left) (Text_range.length right)
           | Some _, None -> -1
           | None, Some _ -> 1
           | None, None ->
               Region_id.compare (Region.id left) (Region.id right))
  in
  match candidates with [] -> None | region :: _ -> Some region

let occurrence_of_link ~artifact ~path regions link =
  let* parsed = parse_link_target path link.destination in
  let* target =
    match parsed with
    | Direct_target address -> Ok (Reference_occurrence.Direct address)
    | Named_reference (_, local) ->
        let* id =
          Reference_id.make ~artifact ~local:(Identifier.to_string local)
        in
        Ok (Reference_occurrence.Named id)
  in
  let source_region =
    containing_region regions link.range |> Option.map Region.id
  in
  Reference_occurrence.make ~source_artifact:artifact ?source_region
    ~range:link.range ~target ()

let annotation_from_marker ~artifact regions = function
  | Region_marker _ -> Ok None
  | Annotation_marker { local; predicate; reference; range } -> (
      match preceding_region regions range with
      | None -> Error ("monika:annotation " ^ local ^ " has no preceding region")
      | Some region ->
          let* id = Annotation_id.make ~artifact ~local in
          let* reference = Reference_id.make ~artifact ~local:reference in
          let* provenance = Provenance.make ~source:"markdown-inline" () in
          Annotation.make ~id
            ~subject:(Annotation.Region (Region_ref.Resolved (Region.id region)))
            ~predicate ~object_:(Annotation.Reference_object reference)
            ~provenance:[ provenance ]
            ~materialization:[ Annotation.Markdown_inline { artifact; range } ]
          |> Result.map Option.some)

let collect_optional make values =
  List.fold_left
    (fun result value ->
      let* acc = result in
      let* item = make value in
      Ok (match item with None -> acc | Some item -> item :: acc))
    (Ok []) values
  |> Result.map List.rev

let collect_references ~artifact ~path links =
  let merge result link =
    let* order, references = result in
    let* candidate = reference_of_link ~artifact ~path link in
    match candidate with
    | None -> Ok (order, references)
    | Some candidate -> (
        let id = Reference.id candidate in
        match Reference_map.find_opt id references with
        | None ->
            Ok (id :: order, Reference_map.add id candidate references)
        | Some existing ->
            if
              Reference.compare_target (Reference.target existing)
                (Reference.target candidate)
              <> 0
            then Error "Markdown links with the same reference ID disagree"
            else
              let combined =
                Reference.make ~id:(Reference.id existing)
                  ~target:(Reference.target existing)
                  ~binding:(Reference.binding existing)
                  ~expectations:(Reference.expectations existing)
                  ~provenance:
                    (Reference.provenance existing
                    @ Reference.provenance candidate)
                  ()
              in
              Ok (order, Reference_map.add id combined references))
  in
  List.fold_left merge (Ok ([], Reference_map.empty)) links
  |> Result.map (fun (order, references) ->
         List.rev_map (fun id -> Reference_map.find id references) order)

let has_duplicate compare id values =
  let sorted = List.sort (fun left right -> compare (id left) (id right)) values in
  let rec adjacent = function
    | left :: (right :: _ as rest) ->
        compare (id left) (id right) = 0 || adjacent rest
    | [] | [ _ ] -> false
  in
  adjacent sorted

let inspect ~artifact ~path content =
  if not (Utf8.is_valid content) then Error "Markdown artifact must be valid UTF-8"
  else
    let document = Cmarkit.Doc.of_string ~layout:true ~locs:true content in
    let observation_identity =
      Observation_identity.of_content ~observation_type:markdown_type
        (Content_identity.of_content content)
    in
    let blocks = blocks content document in
    let* markers = markers blocks in
    let* regions =
      collect_optional
        (region_from_marker ~artifact ~observation_identity ~content blocks)
        markers
    in
    let links = links document in
    let* references = collect_references ~artifact ~path links in
    let* occurrences =
      List.fold_left
        (fun result link ->
          let* acc = result in
          let* occurrence = occurrence_of_link ~artifact ~path regions link in
          Ok (occurrence :: acc))
        (Ok []) links
      |> Result.map List.rev
    in
    let* annotations =
      collect_optional (annotation_from_marker ~artifact regions) markers
    in
    if has_duplicate Region_id.compare Region.id regions then
      Error "duplicate monika:region ID"
    else if has_duplicate Annotation_id.compare Annotation.id annotations then
      Error "duplicate monika:annotation ID"
    else Ok { regions; references; occurrences; annotations }
