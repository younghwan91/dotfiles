# 정적 검사 정리

**완료 기준**: 아래 검사가 CI 에서 경고 0 으로 돌고, 각 수정은 따로 PR 로 머지됐다. 검증: `main` 의 CI 초록.

1. shellcheck 를 style 수준까지 — 파일마다 고치고, 끝나면 CI 의 `-S warning` 을 `-S style` 로.
2. ruff (`E501` 줄 길이 제외) — 파일마다 고치고 CI 에 추가.
3. `.cmd` 는 CRLF 로 체크아웃(`.gitattributes`) — cmd 는 LF 파일에서 `goto`/레이블을 잘못 찾을 수 있다.
4. PowerShell 은 PSScriptAnalyzer, 워크플로는 actionlint, 오타는 typos — 각각 CI 에 추가하고 나온 것을 고친다.
5. 테스트가 없는 명령(`gh-protect`, `pull-all` 의 personal 레포)에 테스트.
