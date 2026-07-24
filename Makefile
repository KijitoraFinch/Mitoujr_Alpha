.PHONY: phase0-check contract-test report-bundle-test golden-check build-sugar test-sugar distribution-check check-bitter opam-lint check release-check

phase0-check:
	python3 tools/check_phase0.py

contract-test:
	python3 tools/test_json_contract.py
	python3 tools/test_semantic_contract.py

report-bundle-test:
	python3 tools/test_report_bundle.py

golden-check:
	python3 tools/check_golden.py

build-sugar:
	dune build --root sugar @install

test-sugar:
	dune runtest --root sugar

distribution-check:
	python3 tools/check_distribution.py

check-bitter:
	cargo fmt --manifest-path bitter/Cargo.toml -- --check
	cargo clippy --locked --manifest-path bitter/Cargo.toml --all-targets -- -D warnings
	cargo test --locked --manifest-path bitter/Cargo.toml
	python3 tools/check_bitter.py

opam-lint:
	opam lint sugar/monika_sugar.opam

check: phase0-check contract-test report-bundle-test golden-check build-sugar test-sugar distribution-check check-bitter

release-check: check opam-lint
