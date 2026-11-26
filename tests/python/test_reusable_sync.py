"""ci-reusable.yml 的 .NET 步驟有兩份副本，這裡檢查兩份的 run: 內容一致。

2.5.0 起所有 CI 檢查合併在 CI Gate 一個 job（省 Actions 分鐘），但 dotnet-runner 不是
ubuntu-latest 時 .NET 必須在另一台 runner 跑，所以獨立的 dotnet job 保留同一套步驟。
兩份只有 if / continue-on-error / shell 這類外框不同，run: 的腳本必須一字不差，
否則 Linux 與 Windows 的 .NET 專案會得到不同的檢查。

只用標準函式庫逐行比對（CI 只安裝 ruff 與 pytest，沒有 PyYAML）。
"""

import re
from pathlib import Path

WORKFLOW = Path(__file__).resolve().parents[2] / ".github" / "workflows" / "ci-reusable.yml"
STEP_NAME = re.compile(r'^(\s*)- name: "(\.NET: [^"]+)"\s*$')


def _dotnet_run_blocks() -> dict[str, list[str]]:
    """回傳 {步驟名稱: [run 內容（第一份）, run 內容（第二份）, ...]}。"""
    lines = WORKFLOW.read_text(encoding="utf-8").splitlines()
    found: dict[str, list[str]] = {}
    i = 0
    while i < len(lines):
        m = STEP_NAME.match(lines[i])
        if not m:
            i += 1
            continue
        indent, name = len(m.group(1)), m.group(2)
        # 步驟範圍：到下一個同層的 "- " 或縮排更淺的行為止
        j = i + 1
        while j < len(lines):
            s = lines[j]
            lead = len(s) - len(s.lstrip())
            if s.strip() and (lead < indent or (lead == indent and s.lstrip().startswith("- "))):
                break
            j += 1
        step = lines[i:j]
        run = []
        for k, s in enumerate(step):
            stripped = s.strip()
            if stripped.startswith("run:"):
                rest = stripped[len("run:"):].strip()
                if rest and rest != "|":
                    run = [rest]
                else:
                    run_indent = len(s) - len(s.lstrip())
                    for t in step[k + 1:]:
                        if t.strip() and len(t) - len(t.lstrip()) <= run_indent:
                            break
                        run.append(t.strip())
                break
        found.setdefault(name, []).append("\n".join(run).strip())
        i = j
    return found


def test_dotnet_steps_exist_in_both_jobs():
    blocks = _dotnet_run_blocks()
    assert blocks, "找不到任何 .NET: 步驟"
    for name, runs in blocks.items():
        assert len(runs) == 2, f"「{name}」應該在 dotnet job 與 CI Gate 各出現一次，實際 {len(runs)} 次"


def test_dotnet_run_scripts_identical():
    for name, runs in _dotnet_run_blocks().items():
        assert runs[0], f"「{name}」沒有 run: 內容"
        assert runs[0] == runs[1], f"「{name}」兩份 run: 內容不一致，改一邊要同步改另一邊"
