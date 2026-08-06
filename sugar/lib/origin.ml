type t =
  | Workspace of Workspace_path.t
  | Git of { repo : string; rev : string option; path : string }
  | Web of string
  | Generated of string
  | External of string
  | Extension of { provider : string; locator : string }

let nonempty name value =
  if String.length value = 0 then Error (name ^ " must not be empty")
  else if not (Utf8.is_valid value) then Error (name ^ " must be valid UTF-8")
  else Ok value

let workspace path = Workspace path

let git ~repo ?rev ~path () =
  match (nonempty "git repo" repo, nonempty "git path" path) with
  | Error _ as error, _ | _, (Error _ as error) -> error
  | Ok repo, Ok path -> (
      match rev with
      | Some "" -> Error "git rev must not be empty"
      | Some rev when not (Utf8.is_valid rev) ->
          Error "git rev must be valid UTF-8"
      | Some rev -> Ok (Git { repo; rev = Some rev; path })
      | None -> Ok (Git { repo; rev = None; path }))

let web value = Result.map (fun value -> Web value) (nonempty "web url" value)

let generated value =
  Result.map (fun value -> Generated value) (nonempty "generated name" value)

let external_ value =
  Result.map (fun value -> External value) (nonempty "external uri" value)

let extension ~provider ~locator () =
  match
    (nonempty "extension origin provider" provider,
     nonempty "extension origin locator" locator)
  with
  | Error _ as error, _ | _, (Error _ as error) -> error
  | Ok provider, Ok locator -> Ok (Extension { provider; locator })

let rank = function
  | Workspace _ -> 0
  | Git _ -> 1
  | Web _ -> 2
  | Generated _ -> 3
  | External _ -> 4
  | Extension _ -> 5

let compare left right =
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
  | Extension left, Extension right -> (
      match String.compare left.provider right.provider with
      | 0 -> String.compare left.locator right.locator
      | other -> other)
  | _ -> Int.compare (rank left) (rank right)

let equal left right = compare left right = 0
