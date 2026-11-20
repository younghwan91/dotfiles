# 공개 레포 분리

**완료 기준**: `<owner>/dotfiles` 가 공개이고, 히스토리는 새로 시작한 커밋뿐이며 작성자는 noreply,
트리에 `personal/` 이 없고 `check_no_personal.py`(개인 패턴 포함) 0 hit. 개인 값은 비공개
`<owner>/dotfiles-personal` 에 있고 `~/git/dotfiles/personal/` 에 clone 된다. 옛 히스토리는
남기지 않는다(`dotfiles-archive` 는 확인 뒤 삭제). 검증: 로컬 테스트 전부 통과, GitHub Actions 통과,
익명 `curl` 로 옛 커밋 SHA 가 공개 레포 API 에서 404.

## 단계

1. `install.sh` 가 `DOTFILES_PERSONAL`(기본 `$repo/personal`)을 읽고, personal 프로필인데 없으면
   `dotfiles-personal` 을 clone. 테스트는 가짜 personal 디렉터리를 쓴다.
2. `personal/` 을 `.gitignore` 로 빼고 README 정리. 메일을 noreply 로.
3. `personal/` 내용으로 비공개 `dotfiles-personal` 생성.
4. 옛 레포를 `dotfiles-archive` 로 이름 변경, 새 공개 `dotfiles` 에 단일 커밋 push. 확인 뒤 archive 삭제.
5. 이 머신의 체크아웃을 새 레포로 맞춘다. 다른 기기는 손으로 다시 맞춤.

완료 (2026-11-21): 위 기준 전부 확인. 이 머신과 다른 리눅스 호스트 전환 끝, Windows PC 는 남음.
