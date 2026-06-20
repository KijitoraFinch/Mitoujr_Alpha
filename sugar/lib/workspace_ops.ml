type applied = {
  snapshot : Workspace_snapshot.t;
  changed : Command_result.changed_artifact;
}

type result =
  | Applied of applied
  | No_change of Workspace_snapshot.t
  | Conflict of Conflict.t

let first_invalid_range ~patch_id ~target ~content_length edits =
  List.find_map
    (fun edit ->
      let range = Text_edit.range edit in
      if Text_range.end_ range > content_length then
        Some
          (Conflict.Range_out_of_bounds
             { patch_id; target; range; content_length })
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
            (Conflict.Overlapping_edits
               {
                 patch_id;
                 target;
                 left = Text_edit.range left;
                 right = Text_edit.range right;
               })
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
  match Workspace_snapshot.find target snapshot with
  | None -> Conflict (Conflict.Missing_artifact { patch_id; target })
  | Some file ->
      let current_identity = Workspace_snapshot.file_identity file in
      if
        Content_identity.equal current_identity
          (Proposed_patch.resulting_identity patch)
      then No_change snapshot
      else if
        not
          (Content_identity.equal current_identity
             (Proposed_patch.expected_identity patch))
      then
        Conflict
          (Conflict.Identity_mismatch
             {
               patch_id;
               target;
               expected = Proposed_patch.expected_identity patch;
               actual = current_identity;
             })
      else
        let edits = List.sort Text_edit.compare (Proposed_patch.edits patch) in
        let content = Workspace_snapshot.file_content file in
        let content_length = String.length content in
        match first_invalid_range ~patch_id ~target ~content_length edits with
        | Some conflict -> Conflict conflict
        | None -> (
            match first_overlap ~patch_id ~target edits with
            | Some conflict -> Conflict conflict
            | None ->
                let result_content = apply_edits content edits in
                let result_identity =
                  Content_identity.of_content result_content
                in
                if
                  not
                    (Content_identity.equal result_identity
                       (Proposed_patch.resulting_identity patch))
                then
                  Conflict
                    (Conflict.Result_identity_mismatch
                       {
                         patch_id;
                         target;
                         declared = Proposed_patch.resulting_identity patch;
                         actual = result_identity;
                       })
                else
                  Applied
                    {
                      snapshot =
                        Workspace_snapshot.replace_content target result_content
                          snapshot;
                      changed =
                        {
                          Command_result.path = target;
                          before = current_identity;
                          after = result_identity;
                        };
                    })
