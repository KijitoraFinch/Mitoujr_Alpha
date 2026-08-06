type binding = Pinned | Tracking | Floating

type target = Region_address.t

type t = {
  id : Reference_id.t;
  target : target;
  binding : binding;
  expectations : Expectation.t list;
  provenance : Provenance.t list;
}

let make_target = Region_address.make

let make ~id ~target ~binding ?(expectations = []) ?(provenance = []) () =
  { id; target; binding; expectations; provenance }

let id value = value.id
let target value = value.target
let binding value = value.binding
let expectations value = value.expectations
let provenance value = value.provenance
let target_artifact = Region_address.artifact
let target_selector = Region_address.selector
let target_interpreter = Region_address.interpreter
let target_interpreter_version = Region_address.interpreter_version

let compare_target = Region_address.compare
