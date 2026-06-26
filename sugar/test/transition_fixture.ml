open Monika_sugar

let get = function Ok value -> value | Error message -> failwith message

let path value = get (Workspace_path.of_canonical_string value)
let range start end_ = get (Text_range.make ~start ~end_)
let edit start end_ replacement = Text_edit.make ~range:(range start end_) ~replacement

let patch ~id ~target ~expected ~resulting ~edits ~reason =
  let provenance = get (Provenance.make ~source:"transition-fixture" ()) in
  get
    (Proposed_patch.make ~id:(get (Identifier.make id)) ~target
       ~expected_identity:(Content_identity.of_content expected)
       ~resulting_identity:(Content_identity.of_content resulting)
       ~edits ~reason ~provenance)

type transition_case = {
  case_id : string;
  initial : Workspace_snapshot.t;
  patch : Proposed_patch.t;
}

let make_case ~case_id ~target ~initial_content ~patch =
  {
    case_id;
    initial = get (Workspace_snapshot.make [ (target, initial_content) ]);
    patch;
  }

let title_case =
  let target = path "notes/title.txt" in
  make_case ~case_id:"apply-title-replacement" ~target
    ~initial_content:"Title\n"
    ~patch:
      (patch ~id:"patch:title" ~target ~expected:"Title\n"
         ~resulting:"Heading\n"
         ~edits:[ edit 0 5 "Heading" ]
         ~reason:"Normalize the title")

let identity_mismatch_case =
  let target = path "notes/title.txt" in
  make_case ~case_id:"apply-identity-mismatch" ~target
    ~initial_content:"Title\n"
    ~patch:
      (patch ~id:"patch:identity-mismatch" ~target ~expected:"Other\n"
         ~resulting:"Heading\n"
         ~edits:[ edit 0 5 "Heading" ]
         ~reason:"Demonstrate identity mismatch")

let range_out_of_bounds_case =
  let target = path "notes/range.txt" in
  make_case ~case_id:"apply-range-out-of-bounds" ~target
    ~initial_content:"abc"
    ~patch:
      (patch ~id:"patch:range-out-of-bounds" ~target ~expected:"abc"
         ~resulting:"abZ"
         ~edits:[ edit 2 4 "Z" ]
         ~reason:"Demonstrate out-of-bounds range")

let overlap_case =
  let target = path "notes/overlap.txt" in
  make_case ~case_id:"apply-overlap" ~target ~initial_content:"abcdef"
    ~patch:
      (patch ~id:"patch:overlap" ~target ~expected:"abcdef"
         ~resulting:"aXYef"
         ~edits:[ edit 1 3 "X"; edit 2 4 "Y" ]
         ~reason:"Demonstrate overlapping edits")

let result_identity_mismatch_case =
  let target = path "notes/result.txt" in
  make_case ~case_id:"apply-result-identity-mismatch" ~target
    ~initial_content:"abcdef"
    ~patch:
      (patch ~id:"patch:result-identity-mismatch" ~target
         ~expected:"abcdef" ~resulting:"declared"
         ~edits:[ edit 0 1 "A" ]
         ~reason:"Demonstrate result identity mismatch")

let repeated_no_op_case =
  let target = path "notes/repeated.txt" in
  make_case ~case_id:"apply-repeated-no-op" ~target
    ~initial_content:"aXYZc"
    ~patch:
      (patch ~id:"patch:repeated-no-op" ~target ~expected:"abc"
         ~resulting:"aXYZc"
         ~edits:[ edit 1 2 "XYZ" ]
         ~reason:"Demonstrate repeated apply no-op")

let cases =
  [
    title_case;
    identity_mismatch_case;
    range_out_of_bounds_case;
    overlap_case;
    result_identity_mismatch_case;
    repeated_no_op_case;
  ]

let command_result ?(summary = []) ~effect ?(changed_artifacts = [])
    ?(conflicts = []) () =
  get
    (Command_result.make ~command:"apply"
       ~termination:Command_result.Completed ~effect ~changed_artifacts
       ~conflicts ~summary ())

let transition_result case =
  match Workspace_ops.apply_patch case.initial case.patch with
  | Workspace_ops.Applied value ->
      ( value.snapshot,
        command_result ~effect:Command_result.Applied
          ~changed_artifacts:[ value.changed ]
          ~summary:[ ("applied", Command_result.Count 1) ] () )
  | Workspace_ops.No_change snapshot ->
      ( snapshot,
        command_result ~effect:Command_result.No_change
          ~summary:[ ("applied", Command_result.Count 0) ] () )
  | Workspace_ops.Conflict conflict ->
      ( case.initial,
        command_result ~effect:Command_result.Conflicted
          ~conflicts:[ conflict ]
          ~summary:[ ("conflicts", Command_result.Count 1) ] () )

let transition_json case =
  let final_snapshot, result = transition_result case in
  let normalized_result = Normal.Command_result.normalize result in
  `Assoc
    [
      ("schemaVersion", `String "1");
      ("caseId", `String case.case_id);
      ( "initialSnapshot",
        case.initial |> Normal.Workspace_snapshot.normalize
        |> Normal_json.workspace_snapshot );
      ( "command",
        `Assoc
          [
            ("name", `String "apply");
            ( "patch",
              case.patch |> Normal.Patch.normalize |> Normal_json.patch );
          ] );
      ("result", Normal_json.command_result normalized_result);
      ( "finalSnapshot",
        final_snapshot |> Normal.Workspace_snapshot.normalize
        |> Normal_json.workspace_snapshot );
      ("exitClass", `String normalized_result.exit_class);
    ]

let find_case id =
  List.find_opt (fun case -> String.equal case.case_id id) cases

let selected_case () =
  match Array.to_list Sys.argv with
  | [ _program ] -> title_case
  | [ _program; case_id ] -> (
      match find_case case_id with
      | Some case -> case
      | None ->
          failwith
            ("unknown transition case: " ^ case_id ^ "; available: "
           ^ String.concat ", " (List.map (fun case -> case.case_id) cases)))
  | _ -> failwith "usage: transition_fixture.exe [case-id]"

let () =
  selected_case () |> transition_json |> Yojson.Safe.pretty_to_channel stdout;
  print_newline ()
