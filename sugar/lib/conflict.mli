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

val compare : t -> t -> int
val target : t -> Workspace_path.t
val patch_id : t -> Identifier.t
