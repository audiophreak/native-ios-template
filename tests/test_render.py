"""What the native layer renders, what it must not touch, and what must never be in it."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

import pytest
import yaml

from conftest import TEMPLATE_ROOT, render

IOS_TOP = {".gitignore", "AGENTS.md", "CLAUDE.md", "README.md", "App", "App.xcodeproj", "AppTests", "Config", "Contract", "Packages", "Tools", "scripts"}
ANSWERS = ".copier-answers.ios.yml"


def files(root: Path) -> set[str]:
    return {str(p.relative_to(root)) for p in root.rglob("*") if p.is_file()}


def test_it_renders_only_ios_and_its_own_answers_file(rendered: Path) -> None:
    assert {p.name for p in rendered.iterdir()} == {"ios", ANSWERS}
    assert {p.name for p in (rendered / "ios").iterdir()} == IOS_TOP
    assert all(name == ANSWERS or name.startswith("ios/") for name in files(rendered))


def test_the_answers_file_is_separate_and_records_the_release_and_answers(rendered: Path) -> None:
    answers = yaml.safe_load((rendered / ANSWERS).read_text())
    assert answers["app_name"] == "sample-app" and answers["bundle_identifier"] == "com.example.sampleapp"
    assert answers["debug_api_port"] == 3000 and answers["release_api_host"] == "api.example.com" and answers["_commit"]
    assert not (rendered / ".copier-answers.yml").exists()


def test_applying_it_to_a_web_project_changes_none_of_the_web_projects_files(template_repo: Path, tmp_path: Path) -> None:
    project = tmp_path / "web"
    (project / "src").mkdir(parents=True)
    web = {
        ".copier-answers.yml": "_commit: v0.7.0\napp_name: sample-app\nauth: true\nnative_client: true\n",
        "package.json": '{"name":"sample-app"}\n', "AGENTS.md": "web rules\n", "CLAUDE.md": "@AGENTS.md\n",
        ".gitignore": "node_modules\n", "README.md": "web readme\n", "src/page.tsx": "export default 1\n",
    }  # fmt: skip
    for name, text in web.items():
        (project / name).write_text(text)
    before = {name: (project / name).read_bytes() for name in web}
    render(template_repo, project, app_name="sample-app")
    assert {name: (project / name).read_bytes() for name in web} == before
    assert (project / "ios/App.xcodeproj/project.pbxproj").is_file() and (project / ANSWERS).is_file()
    assert yaml.safe_load((project / ".copier-answers.yml").read_text())["_commit"] == "v0.7.0"  # the web layer's own record


@pytest.mark.parametrize(
    ("answers", "message"),
    [
        ({"app_name": "Bad_Name"}, "lowercase letters"), ({"app_name": "9app"}, "lowercase letters"), ({"app_name": "a" * 65}, "1-64"),
        ({"app_display_name": "Has/Slash"}, "ASCII letters"), ({"app_display_name": "x" * 31}, "30"),
        ({"bundle_identifier": "single"}, "reverse-DNS"), ({"bundle_identifier": "com.example.has space"}, "reverse-DNS"),
        ({"bundle_identifier": "com..example"}, "reverse-DNS"), ({"debug_api_port": 80}, "1024"), ({"debug_api_port": 70000}, "65535"),
        ({"release_api_host": "https://api.example.com"}, "host name"), ({"release_api_host": "user:pw@api.example.com"}, "host name"),
        ({"release_api_host": "localhost"}, "host name"), ({"release_api_host": "api.example.com/path"}, "host name"),
    ],
)  # fmt: skip
def test_invalid_answers_fail_before_anything_is_written(template_repo: Path, tmp_path: Path, answers: dict, message: str) -> None:
    destination = tmp_path / "no"
    with pytest.raises(Exception, match=message):
        render(template_repo, destination, **answers)
    assert not destination.exists()


def test_answers_flow_into_the_configuration_files_only(template_repo: Path, tmp_path: Path) -> None:
    custom = tmp_path / "custom"
    render(template_repo, custom, app_name="my-notes", app_display_name="My Notes", bundle_identifier="org.acme.notes", debug_api_port=4100, release_api_host="api.acme.org:8443")
    shared = (custom / "ios/Config/Shared.xcconfig").read_text()
    assert "APP_DISPLAY_NAME = My Notes" in shared and "PRODUCT_BUNDLE_IDENTIFIER_BASE = org.acme.notes" in shared
    assert "API_HOST = localhost:4100" in (custom / "ios/Config/Debug.xcconfig").read_text()
    assert "API_HOST = api.acme.org:8443" in (custom / "ios/Config/Release.xcconfig").read_text()
    default = tmp_path / "default"
    render(template_repo, default, app_name="other-app")
    changing = {name for name in files(custom) if name.startswith("ios/") and (custom / name).read_bytes() != (default / name).read_bytes()}
    assert changing == {"ios/Config/Shared.xcconfig", "ios/Config/Debug.xcconfig", "ios/Config/Release.xcconfig", "ios/AGENTS.md", "ios/README.md"}


def test_the_project_the_client_and_the_swift_sources_are_the_same_for_every_answer(template_repo: Path, tmp_path: Path) -> None:
    one, two = tmp_path / "one", tmp_path / "two"
    render(template_repo, one, app_name="app-one")
    render(template_repo, two, app_name="app-two", bundle_identifier="net.example.two", debug_api_port=5000)
    for name in files(one):
        if name.startswith(("ios/App.xcodeproj", "ios/Packages", "ios/App/", "ios/AppTests", "ios/Contract", "ios/Tools", "ios/scripts")):
            assert (one / name).read_bytes() == (two / name).read_bytes(), name


def test_no_secret_credential_team_or_personal_path_is_rendered(rendered: Path) -> None:
    # check-static.sh contains the patterns it searches for, so it is the one file not scanned for them
    text = {name: (rendered / name).read_text(errors="replace") for name in files(rendered) if not name.endswith(".png") and not name.endswith("check-static.sh")}
    joined = "\n".join(text.values())
    assert not re.search(r"gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY", joined)
    assert not re.search(r"/Users/|/home/[a-z]|McCauley|audiophreak", joined)
    assert not re.search(r"DEVELOPMENT_TEAM *= *[A-Z0-9]{6,}", joined) and "DEVELOPMENT_TEAM" not in (rendered / "ios/App.xcodeproj/project.pbxproj").read_text()
    joined = "\n".join(v for k, v in text.items() if not k.endswith(".gitignore"))  # the ignore file names the signing material it excludes
    assert not re.search(r"\.mobileprovision|\.p12|CODE_SIGN_IDENTITY *= *[\"']?(iPhone|Apple) ", joined)
    assert not (set(files(rendered)) & {n for n in files(rendered) if n.endswith((".p12", ".cer", ".mobileprovision", ".env", ".env.local"))})


def test_transport_security_is_configured_per_build_and_never_globally_disabled(rendered: Path) -> None:
    debug = (rendered / "ios/Config/Info-Debug.plist").read_text()
    release = (rendered / "ios/Config/Info-Release.plist").read_text()
    assert "<key>NSAllowsLocalNetworking</key>" in debug and "NSAllowsArbitraryLoads" not in debug
    assert "NSAppTransportSecurity" not in release  # the system default applies: https, valid certificates
    for sources in (rendered / "ios").rglob("*"):
        if sources.suffix in {".swift", ".plist", ".xcconfig", ".pbxproj"} and ".build" not in sources.parts and "AppTests" not in sources.parts and "Tests" not in sources.parts:
            assert "NSAllowsArbitraryLoads" not in sources.read_text(errors="replace"), sources
    assert "API_SCHEME = http\n" in (rendered / "ios/Config/Debug.xcconfig").read_text()
    assert "API_SCHEME = https\n" in (rendered / "ios/Config/Release.xcconfig").read_text()
    assert "INFOPLIST_FILE = Config/Info-Release.plist" in (rendered / "ios/Config/Release.xcconfig").read_text()


def test_the_deployment_target_is_deliberate_and_documented(rendered: Path) -> None:
    assert "IPHONEOS_DEPLOYMENT_TARGET = 17.0" in (rendered / "ios/Config/Shared.xcconfig").read_text()
    assert ".iOS(.v17)" in (rendered / "ios/Packages/AppCore/Package.swift").read_text()
    assert "iOS 17.0" in (rendered / "ios/README.md").read_text() or "**17.0**" in (rendered / "ios/README.md").read_text()


def test_the_documentation_covers_the_rules_and_both_agent_files_exist(rendered: Path) -> None:
    agents = (rendered / "ios/AGENTS.md").read_text()
    for phrase in ("Keychain", "Never edit it by hand", "sync-contract.sh", "NSAllowsArbitraryLoads", "No signing identity", "../.copier-answers.yml"):
        assert phrase in agents, phrase
    assert (rendered / "ios/CLAUDE.md").read_text().strip() == "@AGENTS.md"
    assert "Minimum iOS" in (rendered / "ios/README.md").read_text()


def test_the_scripts_are_executable_posix_shell_and_node(rendered: Path) -> None:
    for script in (rendered / "ios/scripts").glob("*.sh"):
        assert script.stat().st_mode & 0o111, script.name
        assert subprocess.run(["sh", "-n", str(script)], capture_output=True).returncode == 0, script.name
    assert subprocess.run(["node", "--check", str(rendered / "ios/scripts/e2e.mjs")], capture_output=True).returncode == 0


def test_the_static_checks_pass_on_the_rendered_layer(rendered: Path) -> None:
    result = subprocess.run(["sh", "scripts/check-static.sh"], cwd=rendered / "ios", capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


def test_the_static_checks_actually_catch_what_they_claim_to(rendered: Path, tmp_path: Path) -> None:
    probe = tmp_path / "ios"
    subprocess.run(["cp", "-R", str(rendered / "ios"), str(probe)], check=True)
    sources = probe / "Packages/AppCore/Sources/AppCore"
    for name, line in {
        "A.swift": 'let x = "NSAllowsArbitraryLoads"', "B.swift": 'print("token \\(token)")', "C.swift": 'UserDefaults.standard.set(token, forKey: "k")',
        "D.swift": "func urlSession(_ s: URLSession, didReceiveChallenge c: URLAuthenticationChallenge) {}", "E.swift": 'let u = URL(string: "http://example.com")',
    }.items():  # fmt: skip
        (sources / name).write_text(line + "\n")
        result = subprocess.run(["sh", "scripts/check-static.sh"], cwd=probe, capture_output=True, text=True)
        assert result.returncode == 1, name
        (sources / name).write_text("// clean\n")
    assert subprocess.run(["sh", "scripts/check-static.sh"], cwd=probe, capture_output=True, text=True).returncode == 0


def test_the_ios_gitignore_keeps_build_products_and_signing_material_out(rendered: Path) -> None:
    ignore = (rendered / "ios/.gitignore").read_text().splitlines()
    for entry in ("DerivedData/", ".build/", "xcuserdata/", "*.xcresult", "*.mobileprovision", "*.p12", ".derived-data/"):
        assert entry in ignore, entry


def test_the_template_has_no_destructive_command_in_its_code_or_docs() -> None:
    pattern = re.compile(r"\brm\s+-[a-zA-Z]*[rf]|find\b.*-delete|git\s+clean|git\s+reset\s+--hard|push\s+(-f|--force)|chmod\s+-R|chown\s+-R")
    for path in TEMPLATE_ROOT.rglob("*"):
        if not path.is_file() or any(part in {".git", ".venv", ".build", ".derived-data", "DerivedData", "__pycache__"} for part in path.parts):
            continue
        if path.relative_to(TEMPLATE_ROOT).as_posix() in {"tests/test_render.py", "AGENTS.md"}:
            continue  # the test names the patterns, and AGENTS.md states the rule they enforce
        if path.suffix in {".sh", ".mjs", ".py", ".md", ".yml", ".yaml", ".jinja", ".swift"}:
            assert not pattern.search(path.read_text(errors="replace")), path.relative_to(TEMPLATE_ROOT)
