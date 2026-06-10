.PHONY: phase0-check golden-check build-sugar check-bitter check

phase0-check:
	python3 tools/check_phase0.py

golden-check:
	python3 tools/check_golden.py

build-sugar:
	dune build --root sugar

check-bitter:
	cargo check --manifest-path bitter/Cargo.toml

check: phase0-check golden-check build-sugar check-bitter
