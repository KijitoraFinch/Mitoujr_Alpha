type t = { occurrences : Annotation_occurrence.t list }

let belongs_to observation occurrence =
  match Annotation_occurrence.source occurrence with
  | Source_location.In_observation source ->
      Observation_id.equal source.observation (Observation.id observation)
  | Source_location.In_sidecar _ -> false

let make ~observation ~occurrences =
  if List.for_all (belongs_to observation) occurrences then
    Ok { occurrences = List.sort Annotation_occurrence.compare occurrences }
  else
    Error
      "annotation extraction occurrences must be located in the input observation"

let occurrences value = value.occurrences
