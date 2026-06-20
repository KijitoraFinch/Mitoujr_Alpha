module Path_map = Map.Make (Workspace_path)

type file = {
  path : Workspace_path.t;
  content : string;
  identity : Content_identity.t;
}

type t = file Path_map.t

let make entries =
  let add result (path, content) =
    Result.bind result (fun files ->
        if Path_map.mem path files then
          Error
            ("duplicate workspace path: "
            ^ Workspace_path.to_canonical_string path)
        else
          Ok
            (Path_map.add path
               {
                 path;
                 content;
                 identity = Content_identity.of_content content;
               }
               files))
  in
  List.fold_left add (Ok Path_map.empty) entries

let file_path file = file.path
let file_content file = file.content
let file_identity file = file.identity
let files snapshot = Path_map.bindings snapshot |> List.map snd
let find path snapshot = Path_map.find_opt path snapshot

let replace_content path content snapshot =
  Path_map.add path
    { path; content; identity = Content_identity.of_content content }
    snapshot

let equal left right =
  Path_map.equal
    (fun left right ->
      String.equal left.content right.content
      && Content_identity.equal left.identity right.identity)
    left right
