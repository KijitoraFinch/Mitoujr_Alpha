PYTHON ?= python3

.PHONY: phase0-check contract-test report-bundle-test release-asset-test golden-check build-sugar test-sugar distribution-check check-bitter opam-lint check release-check

phase0-check:
	$(PYTHON) tools/check_phase0.py

contract-test:
	$(PYTHON) tools/test_json_contract.py
	$(PYTHON) tools/test_semantic_contract.py

report-bundle-test:
	$(PYTHON) tools/test_report_bundle.py

release-asset-test:
	$(PYTHON) tools/test_release_assets.py

golden-check:
	$(PYTHON) tools/check_golden.py

build-sugar:
	dune build --root sugar @install

test-sugar:
	dune runtest --root sugar

distribution-check:
	$(PYTHON) tools/check_distribution.py

check-bitter:
	cargo fmt --manifest-path bitter/Cargo.toml -- --check
	cargo clippy --locked --manifest-path bitter/Cargo.toml --all-targets -- -D warnings
	cargo test --locked --manifest-path bitter/Cargo.toml
	$(PYTHON) tools/check_bitter.py

opam-lint:
	opam lint sugar/monika_sugar.opam

check: phase0-check contract-test report-bundle-test release-asset-test golden-check build-sugar test-sugar distribution-check check-bitter

release-check: check opam-lint
