"""What needs Xcode: the generated client is reproducible, the package passes, the app builds for the simulator and
the Release build requires https. Skipped without Xcode; CI runs them on a macOS runner. No signing is involved."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.xcode, pytest.mark.skipif(shutil.which("xcodebuild") is None, reason="needs Xcode")]


def sh(args: list[str], cwd: Path, timeout: int = 1800) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False)


@pytest.fixture(scope="module")
def ios(rendered: Path) -> Path:
    return rendered / "ios"


def test_the_committed_client_is_exactly_what_the_pinned_generator_produces(ios: Path) -> None:
    result = sh(["sh", "scripts/check-generated.sh"], ios)
    assert result.returncode == 0, (result.stdout + result.stderr)[-3000:]


def test_the_contract_check_follows_the_web_projects_contract(ios: Path) -> None:
    assert sh(["sh", "scripts/check-contract.sh"], ios).returncode == 0  # no ../openapi next to the test project: checksum only
    web = ios.parent / "openapi"
    web.mkdir()
    shutil.copy2(ios / "Contract/openapi.json", web / "openapi.json")
    assert sh(["sh", "scripts/check-contract.sh"], ios).returncode == 0
    (web / "openapi.json").write_text((web / "openapi.json").read_text().replace('"1.0.0"', '"1.1.0"', 1))
    stale = sh(["sh", "scripts/check-contract.sh"], ios)
    assert stale.returncode == 1 and "sync-contract" in stale.stderr


def test_the_package_tests_pass(ios: Path) -> None:
    result = sh(["swift", "test"], ios / "Packages/AppCore")
    assert result.returncode == 0, (result.stdout + result.stderr)[-4000:]
    assert "Test run with" in result.stdout + result.stderr and "failed" not in (result.stdout + result.stderr).split("Test run with")[-1].splitlines()[0]


def test_the_app_builds_for_the_simulator_without_signing_and_resolution_uses_the_committed_pins(ios: Path) -> None:
    sim = sh(["sh", "scripts/simulator.sh"], ios)
    assert sim.returncode == 0, sim.stderr
    result = sh(["xcodebuild", "build", "-project", "App.xcodeproj", "-scheme", "App", "-destination", f"id={sim.stdout.strip()}", "-derivedDataPath", ".derived-data/build", "-onlyUsePackageVersionsFromResolvedFile"], ios)
    assert result.returncode == 0, (result.stdout + result.stderr)[-4000:]
    assert (ios / ".derived-data/build/Build/Products/Debug-iphonesimulator/App.app").is_dir()



def test_the_release_build_requires_https_and_has_no_transport_security_exception(ios: Path) -> None:
    result = sh(["sh", "scripts/check-release-config.sh"], ios)
    assert result.returncode == 0, (result.stdout + result.stderr)[-3000:]
    assert "https://api.example.com" in result.stdout and "no App Transport Security exception" in result.stdout
