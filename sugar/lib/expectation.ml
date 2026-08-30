type t =
  | Observation_identity of Observation_identity.t
  | Content_identity of Content_identity.t
  | Revision of Revision.t
  | Fingerprint of Fingerprint.t

let rank = function
  | Observation_identity _ -> 0
  | Content_identity _ -> 1
  | Revision _ -> 2
  | Fingerprint _ -> 3

let compare left right =
  match left, right with
  | Observation_identity left, Observation_identity right ->
      Observation_identity.compare left right
  | Content_identity left, Content_identity right ->
      Content_identity.compare left right
  | Revision left, Revision right -> Revision.compare left right
  | Fingerprint left, Fingerprint right -> Fingerprint.compare left right
  | _ -> Int.compare (rank left) (rank right)

let matches ~origin ~observation_identity ~content_identity ~fingerprint =
  function
  | Observation_identity expected ->
      Observation_identity.equal expected observation_identity
  | Content_identity expected ->
      Option.fold ~none:false ~some:(Content_identity.equal expected)
        content_identity
  | Revision expected ->
      Revision.of_origin origin
      |> Option.fold ~none:false ~some:(Revision.equal expected)
  | Fingerprint expected ->
      Option.fold ~none:false ~some:(Fingerprint.equal expected) fingerprint
