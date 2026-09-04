type applied = {
  snapshot : Workspace_snapshot.t;
  changed : Command_result.changed_file;
}

type result =
  | Applied of applied
  | No_change of Workspace_snapshot.t
  | Conflict of Conflict.t
  | Internal_error of string

let conflict_result = function
  | Ok conflict -> Conflict conflict
  | Error _ -> Internal_error "construct-conflict"

let first_invalid_range ~patch_id ~target ~content_length edits =
  List.find_map
    (fun edit ->
      let range = Text_edit.range edit in
      if Text_range.end_ range > content_length then
        Some
          (Conflict.range_out_of_bounds ~patch_id ~target ~range ~content_length
          |> conflict_result)
      else None)
    edits

let first_overlap ~patch_id ~target edits =
  let rec loop = function
    | left :: (right :: _ as rest) ->
        if
          Text_range.end_ (Text_edit.range left)
          > Text_range.start (Text_edit.range right)
        then
          Some
            (Conflict.overlapping_edits ~patch_id ~target
               ~left:(Text_edit.range left) ~right:(Text_edit.range right)
            |> conflict_result)
        else loop rest
    | _ -> None
  in
  loop edits

let apply_edits content edits =
  let buffer = Buffer.create (String.length content) in
  let rec loop offset = function
    | [] ->
        Buffer.add_substring buffer content offset
          (String.length content - offset)
    | edit :: rest ->
        let range = Text_edit.range edit in
        let start = Text_range.start range in
        Buffer.add_substring buffer content offset (start - offset);
        Buffer.add_string buffer (Text_edit.replacement edit);
        loop (Text_range.end_ range) rest
  in
  loop 0 edits;
  Buffer.contents buffer

let apply_patch snapshot patch =
  let patch_id = Proposed_patch.id patch in
  let target = Proposed_patch.target patch in
  let resulting_identity = Proposed_patch.resulting_identity patch in
  match (Proposed_patch.operation patch, Workspace_snapshot.find target snapshot) with
  | Proposed_patch.Create { content }, None ->
      let actual = Content_identity.of_content content in
      if not (Content_identity.equal actual resulting_identity) then
        Conflict.result_identity_mismatch ~patch_id ~target
          ~declared:resulting_identity ~actual
        |> conflict_result
      else
        Applied
          {
            snapshot = Workspace_snapshot.replace_content target content snapshot;
            changed =
              {
                Command_result.path = target;
                before = None;
                after = resulting_identity;
              };
          }
  | Proposed_patch.Create _, Some file ->
      let actual = Workspace_snapshot.file_identity file in
      if Content_identity.equal actual resulting_identity then No_change snapshot
      else
        Conflict
          (Conflict.target_already_exists ~patch_id ~target ~actual)
  | Proposed_patch.Edit _, None ->
      Conflict (Conflict.missing_target ~patch_id ~target)
  | Proposed_patch.Edit { expected_identity; edits }, Some file ->
      let current_identity = Workspace_snapshot.file_identity file in
      if
        Content_identity.equal current_identity
          resulting_identity
      then No_change snapshot
      else if
        not (Content_identity.equal current_identity expected_identity)
      then
        Conflict.identity_mismatch ~patch_id ~target
          ~expected:expected_identity ~actual:current_identity
        |> conflict_result
      else
        let edits = List.sort Text_edit.compare edits in
        let content = Workspace_snapshot.file_content file in
        let content_length = String.length content in
        match first_invalid_range ~patch_id ~target ~content_length edits with
        | Some result -> result
        | None -> (
            match first_overlap ~patch_id ~target edits with
            | Some result -> result
            | None ->
                let result_content = apply_edits content edits in
                let result_identity =
                  Content_identity.of_content result_content
                in
                if
                  not
                    (Content_identity.equal result_identity
                       resulting_identity)
                then
                  Conflict.result_identity_mismatch ~patch_id ~target
                    ~declared:resulting_identity ~actual:result_identity
                  |> conflict_result
                else
                  Applied
                    {
                      snapshot =
                        Workspace_snapshot.replace_content target result_content
                          snapshot;
                      changed =
                        {
                          Command_result.path = target;
                          before = Some current_identity;
                          after = result_identity;
                        };
                    })
