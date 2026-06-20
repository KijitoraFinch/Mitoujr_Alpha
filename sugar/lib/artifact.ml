type origin =
  | Workspace of Workspace_path.t
  | Git of { repo : string; rev : string option; path : string }
  | Web of string
  | Generated of string
  | External of string

type t = {
  id : Identifier.t;
  origin : origin;
  media_type : string option;
  content_identity : Content_identity.t;
}

let nonempty name value =
  if String.length value = 0 then Error (name ^ " must not be empty")
  else Ok value

let workspace path = Workspace path

let git ~repo ?rev ~path () =
  match (nonempty "git repo" repo, nonempty "git path" path) with
  | Error _ as error, _ | _, (Error _ as error) -> error
  | Ok repo, Ok path -> (
      match rev with
      | Some "" -> Error "git rev must not be empty"
      | Some rev -> Ok (Git { repo; rev = Some rev; path })
      | None -> Ok (Git { repo; rev = None; path }))

let web value = Result.map (fun value -> Web value) (nonempty "web url" value)

let generated value =
  Result.map (fun value -> Generated value) (nonempty "generated name" value)

let external_ value =
  Result.map (fun value -> External value) (nonempty "external uri" value)

let make ~id ~origin ?media_type ~content_identity () =
  { id; origin; media_type; content_identity }

let id value = value.id
let origin value = value.origin
let media_type value = value.media_type
let content_identity value = value.content_identity

let rank = function
  | Workspace _ -> 0
  | Git _ -> 1
  | Web _ -> 2
  | Generated _ -> 3
  | External _ -> 4

let compare_origin left right =
  match Int.compare (rank left) (rank right) with
  | 0 -> (
      match (left, right) with
      | Workspace left, Workspace right -> Workspace_path.compare left right
      | Git left, Git right -> (
          match String.compare left.repo right.repo with
          | 0 -> (
              match Option.compare String.compare left.rev right.rev with
              | 0 -> String.compare left.path right.path
              | other -> other)
          | other -> other)
      | Web left, Web right
      | Generated left, Generated right
      | External left, External right ->
          String.compare left right
      | _ -> assert false)
  | other -> other
