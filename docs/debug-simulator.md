# DEBUG 시뮬레이터 계정

로그인과 Supabase 데이터 준비 없이 연결된 화면을 반복 검증하기 위한 로컬 fixture다.
`#if DEBUG`와 시뮬레이터 환경 검사를 모두 통과해야 활성화되므로 Release 빌드와 실기기에서는 사용할 수 없다.

## 계정

- `mina`: 미나 · 서울, 대한민국 · ICN
- `sofia`: Sofia · Paris, France · CDG

두 계정은 서로 연결된 상태이며, 실행한 계정이 항상 `나`, 반대 계정이 `상대`가 된다.

## 실행

먼저 Debug 시뮬레이터 빌드를 설치한 뒤 원하는 역할로 실행한다.

```bash
xcrun simctl launch --terminate-running-process booted \
  com.seungwoo.WayToYou -debugAccount mina

xcrun simctl launch --terminate-running-process booted \
  com.seungwoo.WayToYou -debugAccount sofia
```

역할별 로컬 기록을 초기화하려면 `-debugReset YES`를 추가한다.

```bash
xcrun simctl launch --terminate-running-process booted \
  com.seungwoo.WayToYou -debugAccount mina -debugReset YES
```

기존 화면 바로가기도 함께 사용할 수 있다.

```bash
xcrun simctl launch --terminate-running-process booted \
  com.seungwoo.WayToYou -debugAccount mina -previewSheet us
```

`previewSheet` 값은 `compose`, `signal`, `keepsakes`, `us`, `letter`를 지원한다.

## 동작 범위

- 로그인과 온보딩을 건너뛰고 연결된 홈으로 바로 진입한다.
- Heart, Signal, Parcel, 프로필 사진 변경은 해당 역할의 로컬 DEBUG 상태에서 동작한다.
- `mina`와 `sofia` 사이의 실시간 서버 동기화는 흉내 내지 않는다.
- Supabase 인증, Storage 정책, 실제 상대 기기 동기화는 로그인한 실기기에서 별도로 검증한다.
