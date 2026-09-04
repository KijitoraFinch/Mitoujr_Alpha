type t = {
  primary_resources : int;
  observed : int;
  interpreted : int;
  unsupported : int;
  failed : int;
  metadata_discovered : int;
  metadata_decoded : int;
  metadata_failed : int;
  complete : bool;
}

let make ~primary_resources ~observed ~interpreted ~unsupported ~failed
    ~metadata_discovered ~metadata_decoded ~metadata_failed ~complete =
  let counts =
    [
      primary_resources;
      observed;
      interpreted;
      unsupported;
      failed;
      metadata_discovered;
      metadata_decoded;
      metadata_failed;
    ]
  in
  if List.exists (Fun.negate Protocol_integer.is_nonnegative_safe) counts then
    Error "coverage counts must be non-negative protocol-safe integers"
  else if observed > primary_resources then
    Error "coverage observed count exceeds primary resources"
  else if interpreted > observed then
    Error "coverage interpreted count exceeds observed resources"
  else if metadata_decoded + metadata_failed > metadata_discovered then
    Error "metadata coverage outcomes exceed discovered metadata"
  else if complete && (failed <> 0 || metadata_failed <> 0) then
    Error "complete coverage cannot contain failures"
  else
    Ok
      {
        primary_resources;
        observed;
        interpreted;
        unsupported;
        failed;
        metadata_discovered;
        metadata_decoded;
        metadata_failed;
        complete;
      }

let empty =
  {
    primary_resources = 0;
    observed = 0;
    interpreted = 0;
    unsupported = 0;
    failed = 0;
    metadata_discovered = 0;
    metadata_decoded = 0;
    metadata_failed = 0;
    complete = true;
  }

let primary_resources value = value.primary_resources
let observed value = value.observed
let interpreted value = value.interpreted
let unsupported value = value.unsupported
let failed value = value.failed
let metadata_discovered value = value.metadata_discovered
let metadata_decoded value = value.metadata_decoded
let metadata_failed value = value.metadata_failed
let complete value = value.complete

let compare left right =
  Stdlib.compare
    ( left.primary_resources,
      left.observed,
      left.interpreted,
      left.unsupported,
      left.failed,
      left.metadata_discovered,
      left.metadata_decoded,
      left.metadata_failed,
      left.complete )
    ( right.primary_resources,
      right.observed,
      right.interpreted,
      right.unsupported,
      right.failed,
      right.metadata_discovered,
      right.metadata_decoded,
      right.metadata_failed,
      right.complete )

let equal left right = compare left right = 0
