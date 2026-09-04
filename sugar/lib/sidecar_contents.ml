type t = {
  scope : Origin.t;
  annotations : Annotation_occurrence.t list;
  reference_definitions : Reference_definition_occurrence.t list;
}

let make ~scope ~annotations ~reference_definitions =
  { scope; annotations; reference_definitions }

let scope value = value.scope
let annotations value = value.annotations
let reference_definitions value = value.reference_definitions
