type t = private
  | Workspace of Workspace_path.t
  | Git of { repo : string; rev : string option; path : string }
  | Web of string
  | Generated of string
  | External of string
  | Extension of { observer : string; locator : string }

val workspace : Workspace_path.t -> t
val git : repo:string -> ?rev:string -> path:string -> unit -> (t, string) result
val web : string -> (t, string) result
val generated : string -> (t, string) result
val external_ : string -> (t, string) result

val extension :
  observer:string -> locator:string -> unit -> (t, string) result

val compare : t -> t -> int
val equal : t -> t -> bool
