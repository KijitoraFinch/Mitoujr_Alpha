type sidecar_only = Allow | Report

type t = {
  sidecar_only : sidecar_only;
  severity_overrides : (Diagnostic.code * Diagnostic.severity) list;
}

let make ~sidecar_only ~severity_overrides =
  let severity_overrides =
    List.sort
      (fun (left, _) (right, _) ->
        String.compare (Diagnostic.code_string left)
          (Diagnostic.code_string right))
      severity_overrides
  in
  let rec has_duplicate = function
    | (left, _) :: ((right, _) :: _ as rest) ->
        left = right || has_duplicate rest
    | [] | [ _ ] -> false
  in
  if has_duplicate severity_overrides then
    Error "AuditPolicy severity overrides must have unique diagnostic codes"
  else Ok { sidecar_only; severity_overrides }

let default =
  { sidecar_only = Report; severity_overrides = [] }

let sidecar_only value = value.sidecar_only
let severity_overrides value = value.severity_overrides

let severity_for value code =
  List.assoc_opt code value.severity_overrides
  |> Option.value ~default:(Diagnostic.default_severity code)

let apply_to_diagnostic value diagnostic =
  let code = Diagnostic.code diagnostic in
  if code = Diagnostic.Sidecar_only && value.sidecar_only = Allow then None
  else
    Some
      (Diagnostic.with_effective_severity
         (severity_for value code)
         diagnostic)

let apply value diagnostics =
  List.filter_map (apply_to_diagnostic value) diagnostics

let sidecar_only_rank = function Allow -> 0 | Report -> 1

let compare left right =
  match
    Int.compare (sidecar_only_rank left.sidecar_only)
      (sidecar_only_rank right.sidecar_only)
  with
  | 0 -> Stdlib.compare left.severity_overrides right.severity_overrides
  | other -> other
