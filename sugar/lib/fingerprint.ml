type t = Schema_value.t

let make = Schema_value.make

let sha256_schema =
  "https://monika.local/schemas/sha256-fingerprint.schema.json"

let sha256 content =
  let digest =
    Content_digest.of_content content |> Content_digest.to_string
  in
  Schema_value.make ~schema:sha256_schema ~value:(`String digest) ()
  |> Result.get_ok

let schema = Schema_value.schema
let value = Schema_value.value
let compare = Schema_value.compare
let equal = Schema_value.equal
