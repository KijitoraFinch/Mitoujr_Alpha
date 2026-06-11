# Golden Outputs

This directory records observable normal forms and workspace transitions.
Phase 0 command scaffolds remain until the corresponding CLI commands are
implemented.

`normal-form/` values are generated from OCaml semantic fixtures and validated
against JSON Schema. `workspace-transitions/` values contain the schema version,
case ID, initial snapshot, command, normalized command result, final snapshot,
and exit class. Diagnostics and patches occur only inside the command result
except for the patch that is itself the transition command input.
