type t =
  | Missing_artifact of {
      patch_id : Identifier.t;
      target : Workspace_path.t;
    }
  | Identity_mismatch of {
      patch_id : Identifier.t;
      target : Workspace_path.t;
      expected : Content_identity.t;
      actual : Content_identity.t;
    }
  | Result_identity_mismatch of {
      patch_id : Identifier.t;
      target : Workspace_path.t;
      declared : Content_identity.t;
      actual : Content_identity.t;
    }
  | Range_out_of_bounds of {
      patch_id : Identifier.t;
      target : Workspace_path.t;
      range : Text_range.t;
      content_length : int;
    }
  | Overlapping_edits of {
      patch_id : Identifier.t;
      target : Workspace_path.t;
      left : Text_range.t;
      right : Text_range.t;
    }

let target = function
  | Missing_artifact value -> value.target
  | Identity_mismatch value -> value.target
  | Result_identity_mismatch value -> value.target
  | Range_out_of_bounds value -> value.target
  | Overlapping_edits value -> value.target

let patch_id = function
  | Missing_artifact value -> value.patch_id
  | Identity_mismatch value -> value.patch_id
  | Result_identity_mismatch value -> value.patch_id
  | Range_out_of_bounds value -> value.patch_id
  | Overlapping_edits value -> value.patch_id

let rank = function
  | Missing_artifact _ -> 0
  | Identity_mismatch _ -> 1
  | Result_identity_mismatch _ -> 2
  | Range_out_of_bounds _ -> 3
  | Overlapping_edits _ -> 4

let compare left right =
  match Workspace_path.compare (target left) (target right) with
  | 0 -> (
      match Identifier.compare (patch_id left) (patch_id right) with
      | 0 -> Int.compare (rank left) (rank right)
      | other -> other)
  | other -> other
