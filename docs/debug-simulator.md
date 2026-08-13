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

## 도시를 즉시 바꾸기

DEBUG 계정으로 실행한 뒤 설정의 `DEBUG · 도시 테스트`에서 `내 테스트 도시` 또는 `상대 테스트 도시`를 누르면 된다. MapKit 검색 결과를 선택하는 즉시 홈의 지구본, 거리, 시차와 날씨가 갱신되며 서버와 기본 fixture에는 저장되지 않는다.

코드로 반복 실험할 때는 도시 JSON을 실행 환경변수로 전달한다. 필수 필드는 `name`, `country`, `latitude`, `longitude`, `timeZoneID`이고 `id`는 생략할 수 있다.

```bash
SIMCTL_CHILD_WTY_DEBUG_MY_CITY_JSON='{"name":"Bogotá","country":"Colombia","latitude":4.711,"longitude":-74.0721,"timeZoneID":"America/Bogota"}' \
SIMCTL_CHILD_WTY_DEBUG_PARTNER_CITY_JSON='{"name":"Jakarta","country":"Indonesia","latitude":-6.2088,"longitude":106.8456,"timeZoneID":"Asia/Jakarta"}' \
xcrun simctl launch --terminate-running-process booted \
  com.seungwoo.WayToYou -debugAccount mina
```

값이 전달되면 위도 `-90...90`, 경도 `-180...180`, 유효한 IANA 시간대를 검사한다. 잘못된 JSON으로 다른 도시를 캡처하지 않도록 DEBUG 앱을 즉시 실패시킨다.

## 홈 자동 캡처

`scripts/capture-debug-home.sh`는 지정한 시뮬레이터에서 앱을 다시 실행하고 두 도시를 주입한 뒤 첫 홈 화면을 PNG로 저장한다.

```bash
./scripts/capture-debug-home.sh \
  C5919541-6BEA-4A25-92C7-939A469F18F7 \
  '{"name":"Bogotá","country":"Colombia","latitude":4.711,"longitude":-74.0721,"timeZoneID":"America/Bogota"}' \
  '{"name":"Jakarta","country":"Indonesia","latitude":-6.2088,"longitude":106.8456,"timeZoneID":"Asia/Jakarta"}' \
  artifacts/debug-city-tests/png/manual--bogota-jakarta.png
```

카메라 실험 결과는 `artifacts/debug-city-tests/png/` 한 폴더에 있다. 파일명은 `단계--도시쌍.png` 형식이며 `final-camera--problem--*` 8장은 문제 조합, `final-camera--regression--*` 5장은 기존 정상 조합의 최종 회귀 결과다.

## 동작 범위

- 로그인과 온보딩을 건너뛰고 연결된 홈으로 바로 진입한다.
- Heart, Signal, Parcel, 프로필 사진 변경은 해당 역할의 로컬 DEBUG 상태에서 동작한다.
- `mina`와 `sofia` 사이의 실시간 서버 동기화는 흉내 내지 않는다.
- Supabase 인증, Storage 정책, 실제 상대 기기 동기화는 로그인한 실기기에서 별도로 검증한다.
- 실행 환경변수 도시 주입과 설정의 도시 테스트 UI도 DEBUG 시뮬레이터에서만 컴파일·노출된다.
