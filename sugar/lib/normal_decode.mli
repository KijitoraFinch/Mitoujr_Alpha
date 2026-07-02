val workspace_path : Yojson.Safe.t -> (Workspace_path.t, string) result
val content_identity : Yojson.Safe.t -> (Content_identity.t, string) result
val text_range : Yojson.Safe.t -> (Text_range.t, string) result
val text_edit : Yojson.Safe.t -> (Text_edit.t, string) result
val provenance : Yojson.Safe.t -> (Provenance.t, string) result
val proposed_patch : Yojson.Safe.t -> (Proposed_patch.t, string) result
