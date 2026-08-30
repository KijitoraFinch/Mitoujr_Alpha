type resolved = {
  observation_identity : Observation_identity.t;
  content_identity : Content_identity.t;
  region_fingerprint : Fingerprint.t option;
  display : string option;
}

type outcome =
  | Resolved of resolved
  | Not_found
  | Invalid_selector of string
  | Read_failure

val resolve :
  workspace:string -> regions:Region.t list -> Reference.t -> outcome
