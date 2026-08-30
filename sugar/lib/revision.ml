type t = Schema_value.t

let make = Schema_value.make

let git_schema =
  "https://monika.local/schemas/git-revision.schema.json"

let of_origin = function
  | Origin.Git { rev = Some rev; _ } ->
      Schema_value.make ~schema:git_schema ~value:(`String rev) ()
      |> Result.to_option
  | Origin.Workspace _ | Origin.Git { rev = None; _ } | Origin.Web _
  | Origin.Generated _ | Origin.External _ | Origin.Extension _ ->
      None

let schema = Schema_value.schema
let value = Schema_value.value
let compare = Schema_value.compare
let equal = Schema_value.equal
