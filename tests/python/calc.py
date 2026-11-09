"""公版自我測試用的最小 Python 程式，讓本 repo 的 CI 實際跑 Python lint + test（ruff、pytest）。

刻意不放 requirements.txt / pyproject.toml：沒有第三方相依，OSV / Trivy 不會因為上游新 CVE 變紅。
"""


def add(a: int, b: int) -> int:
    return a + b
