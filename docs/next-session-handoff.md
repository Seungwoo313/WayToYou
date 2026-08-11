# Way to You — 다음 채팅 인수인계

작성일: 2026-08-11

작업 폴더: `/Users/seungwoo/Desktop/WayToYou`

브랜치: `codex/product-plan-mvp`

문서 작성 시작 기준 HEAD: `ba6b9b6 feat: add city profile markers`

이 문서는 다음 채팅에서 현재 작업을 다시 조사하지 않고 곧바로 이어가기 위한 기준 문서다. 다음 작업을 시작할 때 이 문서와 `git status`, 최근 `git log`를 먼저 확인한다.

## 1. 지금 바로 이어서 할 일

도시 중심 프로필 마커는 `ba6b9b6 feat: add city profile markers`에서 완료됐다. 다음 구현은 **프로필 마커를 탭했을 때 이름과 도시/국가만 보여주는 작은 정보 UI**다.

다음 단계에서는 다른 기능을 섞지 말고 아래 범위까지만 구현한다.

1. 내 마커와 상대 마커를 탭할 수 있게 한다.
2. 선택된 마커 가까이에 이름과 도시/국가만 간결하게 표시한다.
3. 일반적인 MapKit callout을 쓸지, 현재 흑백 UI에 맞는 작은 custom overlay를 쓸지 기존 홈 레이아웃과 실제 기기 화면을 보고 결정한다.
4. 지구본 팬·핀치·회전·기울기와 충돌하지 않게 한다.
5. 빈 공간을 탭하거나 다른 마커를 선택했을 때 자연스럽게 닫히거나 전환돼야 한다.
6. 선택 상태 변경은 카메라를 초기화하지 않아야 한다.
7. Route 선, 비행 중 소포, 공항 선택은 이 커밋에 넣지 않는다.

첫 커밋의 권장 단위는 `feat: add profile marker details`다.

### 예상 수정 지점

- `WayToYou/Features/Home/GlobeMapView.swift`
  - annotation 선택 이벤트 처리
  - 선택된 마커 정보 UI 표시와 해제
- 필요하면 `WayToYou/App/ContentView.swift`
  - SwiftUI overlay가 더 적합할 때만 최소 상태 연결

### 다음 단계 완료 조건

- 두 마커를 각각 탭하면 올바른 이름과 도시/국가가 보인다.
- 지도 제스처가 기존처럼 자연스럽고 선택 상태가 카메라를 바꾸지 않는다.
- 정보 UI가 상단 시간, 하단 액션과 탭 바를 침범하지 않는다.
- iPhone 17 시뮬레이터 DEBUG 계정 검증 후 `승우의 iPhone`에서 빌드·설치·실행한다.
- 변경분을 확인하고 작은 단위로 커밋한다.

## 2. 최신 제품 결정 — 기존 Product Plan보다 우선

기존 `docs/way-to-you-plan-v2.md`는 온보딩과 지구본에서 공항을 중심으로 설명하지만, 대화에서 아래 방향으로 변경됐다. 아직 모델·UI·Product Plan 문서에는 완전히 반영되지 않았다.

- 프로필의 위치는 **공항이 아니라 도시**다.
- 프로필 마커는 사용자가 고른 도시의 대표 중심 좌표에 둔다.
- 공항은 프로필 설정이나 평상시 홈의 사람 위치가 아니라 **소포를 보낼 때 Route를 정하는 맥락**에서 사용한다.
- 실시간 위치, 상대 현재 위치, 마지막 위치, 백그라운드 추적은 사용하지 않는다.
- 사용자가 `현재 위치로 찾기`를 누를 때만 위치 권한을 요청한다.
- 도시·공항 데이터는 MapKit 검색 결과를 사용하고 운영 코드에 하드코딩 목록을 다시 넣지 않는다.
- `#if DEBUG`의 ICN/CDG 값은 시뮬레이터 fixture일 뿐 제품 데이터가 아니다.

이 결정 때문에 도시 마커 이후에는 `RouteEndpoint`가 항상 공항을 요구하는 현재 구조를 재검토해야 한다. 바로 큰 모델 마이그레이션부터 하지 말고, 먼저 도시 마커를 완성한 뒤 다음 단계에서 아래 중 하나로 정리한다.

- 프로필에는 `RouteCity`만 저장하고 소포 작성 시 공항을 선택한다.
- 또는 기존 endpoint를 임시 호환하되, UI와 지구본에서는 도시만 사용하고 소포 흐름을 구현할 때 모델을 분리한다.

기존 사용자 호환은 요구사항이 아니다. 필요하면 서버 스키마와 로컬 모델을 새 방향에 맞춰 단순하게 바꿔도 된다.

## 3. 반드시 유지할 디자인·UX 원칙

- 전체 UI는 부드럽고 정돈된 기본 iOS 감성을 따른다.
- UI 크롬은 화이트·블랙·중성 그레이 중심이다. 의미 없는 푸른 tint를 다시 넣지 않는다.
- **새 디자인 토큰 레이어를 추가하지 않는다.** 이미 있는 `Palette`, `Metric`만 필요한 만큼 사용한다.
- 애니메이션은 Heart, 크롭 완료, 배송 같은 의미 있는 순간에만 짧게 쓴다.
- 일반 채팅, DM, 읽음 표시, 마지막 접속, 실시간 위치 추적은 만들지 않는다.
- 기존 사용자나 예전 하드코딩 공항 데이터의 호환을 위해 설계를 복잡하게 만들 필요가 없다.
- 기능을 하나씩 구현하고 Git 커밋도 작은 단위로 남긴다.

### Heart 관련 확정 사항

- `Ping`이 아니라 `Heart`라는 이름을 쓴다.
- 버튼을 연타하면 과거 Facebook/Instagram Live처럼 누른 수만큼 하트가 떠오른다.
- `에게서 하트가 왔어요` 같은 설명 문구는 사용하지 않는다.
- 홈의 Heart 액션은 작은 형태로 유지하고 하트 자체는 분홍 계열이다.
- 연타는 최대 50개까지 하나의 Burst로 묶어 서버에 보낸다.

### 프로필 사진 UI 최종 형태

- 프로필 사진을 누르면 `카메라로 촬영`, `앨범에서 선택`, `기본 이미지로 변경` 메뉴가 나온다.
- 앨범/촬영 후 고정된 원형 마스크 안에서 사진만 드래그·핀치 확대한다.
- 원과 실제 크롭 영역은 움직이지 않는다.
- 원 밖도 같은 사진이 보이되 검은 dim으로 잘리지 않을 부분을 표현한다.
- 크롭 화면은 전체 화면 커스텀 UI가 아니라 Apple 기본 sheet다.
- sheet 본문과 내비게이션은 검정, 끌어내리는 drag indicator는 숨긴다.
- 내비게이션 버튼은 커다란 원형 커스텀 아이콘이 아니라 기본 iOS `취소`/`완료` 텍스트 버튼이다.
- 저장 성공 시 상단에 흰 캡슐 토스트가 뜬다. 작은 초록 점이 튀며 원으로 커지고 체크 선이 그려진 뒤 `프로필 사진이 변경되었어요!`가 잠시 보인다.

현재 이 형태를 구현한 파일은 다음과 같다.

- `WayToYou/Features/Profile/ProfileAvatarPicker.swift`
- `WayToYou/Features/Profile/ProfileAvatarCropView.swift`
- `WayToYou/Features/Profile/ProfileAvatarZoomCanvas.swift`
- `WayToYou/Features/Profile/ProfileAvatarSuccessToast.swift`
- `WayToYou/Services/ProfileAvatarProcessor.swift`

이전 SwiftUI 크롭 시도는 `f28826b`에서 제거됐고, 이후 `550d8b6`부터 UIKit `UIScrollView` 기반 고정 마스크 방식으로 다시 구현됐다. 과거 구현을 복원하지 않는다.

## 4. 현재 구현 상태

| 영역 | 현재 상태 | 남은 검증 또는 구현 |
| --- | --- | --- |
| 소스 폴더 정리·3탭 IA | 완료 | 없음 |
| Apple·Google 로그인 UI/클라이언트 | 구현 완료 | 실제 provider 설정과 각 로그인 E2E 재확인 |
| 기존 세션 복원·Keychain 보안 | 구현 완료 | 정상/삭제된 계정 실기기 재확인 |
| 커플 초대·연결 | 구현 완료 | 실제 두 계정 연결 E2E 재확인 |
| MapKit 도시·공항 검색 | 구현 완료 | 최신 결정에 맞춰 도시/공항 책임 분리 필요 |
| 흑백·중성 UI | 반영 완료 | 새 화면에서도 방향 유지 |
| Heart Burst | 클라이언트·RPC 구현 완료 | 두 실제 계정 수신 애니메이션 E2E 확인 |
| Signal | 클라이언트·RPC 구현 완료 | 두 실제 계정 송수신·만료 E2E 확인 |
| 프로필 사진 선택·크롭·기본 이미지 | 구현 완료 | 최신 실기기 UI와 카메라 재확인 |
| 비공개 프로필 사진 Storage/RLS | 원격 적용 완료 | 실제 연결 상대 다운로드 권한 E2E 확인 |
| 프로필 성공 토스트 | 구현 완료 | 실기기 시각·VoiceOver 확인 |
| DEBUG 시뮬레이터 계정 | 완료 | 서버 실시간 동기화는 의도적으로 없음 |
| MapKit 지구본 | 위성 지구본·동적 카메라·도시 프로필 마커 완료 | 마커 탭 정보 UI가 바로 다음 작업 |
| Parcel/Letter/Keepsakes | 로컬 데모 흐름 존재 | 서버 저장·상대 전송·공항 선택·제품 UX 구현 필요 |
| Polaroid·Voice Tape | 미착수 | Product Plan 후속 단계 |
| Widget | 미착수 | Signal/Heart App Intent 포함 설계 필요 |
| 익명 비행기·Shared World | 미착수 | MVP 후반 |

## 5. 완료된 구현 상세

### 앱 구조와 화면 흐름

- Swift 파일을 `App`, `Core`, `Features`, `Services` 및 기능별 폴더로 정리했다.
- 하단 탭을 Product Plan에 맞춰 `홈`, `간직함`, `우리` 3개로 구성했다.
- 로그인되지 않았으면 Apple/Google 로그인 화면, 로그인됐지만 프로필/연결이 없으면 온보딩, 이미 연결된 사용자면 곧바로 연결된 앱을 표시한다.
- 서버에서 삭제된 사용자의 Keychain 세션은 유효한 사용자로 복원하지 않고 로컬 세션을 정리한다.

주요 파일:

- `WayToYou/App/ContentView.swift`
- `WayToYou/Core/State/WayToYouStore.swift`
- `WayToYou/Services/SupabaseSessionController.swift`
- `WayToYou/Features/Authentication/AppleSignInView.swift`
- `WayToYou/Features/Connection/ConnectionOnboardingView.swift`

### MapKit 도시·공항 선택

- 도시 직접 검색과 현재 위치 역지오코딩 추천을 지원한다.
- 도시 선택 후 주변 공항 POI를 MapKit으로 검색한다.
- 위치 권한은 `현재 위치로 찾기` 버튼을 누를 때 요청한다.
- 지구본은 `MKImageryMapConfiguration(elevationStyle: .realistic)`을 사용한다.
- 팬·핀치·회전·기울기·관성은 MapKit 기본 동작을 유지한다.
- 카메라 경계는 투영 붕괴 방지를 위해 위도 **±70°**다.
- 두 사람의 프로필은 공항이 아닌 각 도시의 `latitude/longitude`에 표시한다.
- 마커는 작은 흰 점, 짧은 선, 46pt 원형 사진으로 구성하며 사진이 없으면 기존 이니셜 fallback을 공유한다.
- 사진·이름 변경은 annotation만 동기화하고 현재 카메라와 사용자 조작 상태는 유지한다.
- 최초 카메라를 확정한 다음 메인 루프에서 annotation을 추가한다. 순서가 반대면 MapKit이 첫 제스처 전까지 마커 가시성 재계산을 미루는 현상이 있었다.
- 초기 카메라는 수동으로 잡은 좌표나 거리를 하드코딩하지 않는다. 두 도시의 구면 중점, 실제 하단 UI 여백 비율, 최대 축소 상태를 이용해 계산한다.
- 위도 보정을 적용하되, 준대척 도시 조합에서도 어느 도시도 지구 뒤로 넘어가지 않도록 구면 지평선 여유로 이동량을 제한한다.
- Route line은 아직 없다.

주요 파일:

- `WayToYou/Core/Models/RouteEndpoint.swift`
- `WayToYou/Services/RoutePlaceSearchService.swift`
- `WayToYou/Features/Connection/RouteEndpointPicker.swift`
- `WayToYou/Features/Home/GlobeMapView.swift`

### Heart와 Signal

- Heart는 탭마다 즉시 로컬 하트와 햅틱을 재생하고 짧게 모은 수량을 하나의 서버 Burst로 전송한다.
- 새로 받은 Burst만 원래 개수대로 재생하며 별도 수신 문구를 표시하지 않는다.
- Signal은 사용자가 선택한 상태를 서버에 보내고 앱이 활성화된 동안 최근 상태를 가볍게 동기화한다.
- 두 기능 모두 security-definer RPC 경계를 통해 현재 연결된 상대와만 주고받도록 DB가 구성돼 있다.

주요 파일:

- `WayToYou/Features/Heart/HeartBurstOverlay.swift`
- `WayToYou/Features/Signals/SignalPickerSheet.swift`
- `WayToYou/Core/State/WayToYouStore.swift`
- `WayToYou/Services/SupabaseConnectionService.swift`

### 프로필 사진

- 카메라와 PhotosPicker를 지원한다.
- 입력 이미지는 orientation을 정규화하고 최대 2048px로 축소한 뒤 크롭 화면으로 전달한다.
- `UIScrollView` 기반 핀치·팬으로 사진만 움직이고 고정 원형 마스크로 미리 본다.
- 최종 결과는 원형으로 굽지 않고 512×512 정사각형 JPEG로 저장하며 표시할 때 원형 clip을 적용한다.
- 업로드 경로는 소문자 UUID 기반 `<user-id>/avatar.jpg`다.
- 비공개 `wty-profile-photos` bucket을 사용하며 public URL을 만들지 않는다.
- 업로드 후 `wty_set_profile_avatar`, 기본 이미지 전환 시 `wty_clear_profile_avatar` RPC로 프로필 공개 상태를 갱신한다.
- 사진 제거는 DB 경로를 먼저 끊고 Storage 객체 삭제를 best-effort로 수행한다.

### 로컬 Parcel 데모

- 제목, 편지, 포장지를 선택해 로컬 소포를 만들 수 있다.
- 데모 모드에서는 배송 시간이 100초로 압축된다.
- 상대가 소포를 열고 답장을 보내는 흐름은 현재 서버 사용자가 아니라 결정론적 로컬 시뮬레이션이다.
- `간직함`은 로컬 Parcel과 Signal 기록을 날짜별로 보여준다.
- 따라서 UI 골격은 있지만 실제 상대 전송 기능이 완료된 것으로 보면 안 된다.

## 6. Supabase 상태 — 2026-08-11 직접 확인

Supabase CLI는 프로젝트에 연결돼 있고 로그인도 되어 있다. 문서 작성 중 아래 읽기 전용 명령으로 원격 상태를 다시 확인했다.

```bash
supabase migration list
supabase db push --dry-run
```

확인 결과:

- 아래 6개 migration은 local/remote version이 모두 일치한다.
- `db push --dry-run` 결과는 `Remote database is up to date.`다.
- 현재 추가로 push할 migration은 없다.

적용된 migration:

- `20260810194000_secure_partner_connections.sql`
- `20260811171000_mapkit_route_endpoints.sql`
- `20260811174000_hearts.sql`
- `20260811180500_reset_test_users.sql`
- `20260811190000_signals.sql`
- `20260811193000_profile_photos.sql`

주의사항:

- `20260811180500_reset_test_users.sql`은 적용 시점에 연결/프로필/Heart 관련 테이블을 비우고 `auth.users`를 삭제하는 일회성 개발 초기화였다.
- migration 적용 완료는 앱 E2E 완료를 뜻하지 않는다.
- 실제 Apple/Google 로그인, 두 실제 계정 연결, Heart/Signal 송수신, 상대 프로필 사진 다운로드 권한은 별도로 검증해야 한다.
- 새 도시/공항 모델 결정을 반영하면 추가 migration이 필요할 수 있다.
- 원격 이력이 이상해 보여도 원인을 확인하지 않고 `migration repair`를 실행하지 않는다.

## 7. DEBUG 시뮬레이터 계정

Supabase 로그인과 온보딩 없이 연결된 화면을 반복 검증하기 위한 `#if DEBUG` fixture가 있다.

- `mina`: 미나 · 서울 · ICN
- `sofia`: Sofia · Paris · CDG
- 둘은 같은 가상 연결에 속하며 실행한 계정이 `나`, 반대 계정이 `상대`가 된다.
- 역할별 UserDefaults가 분리돼 있다.
- 두 시뮬레이터 사이의 서버/실시간 동기화는 하지 않는다.
- Release와 실기기에서는 활성화되지 않는다.

실행 예:

```bash
xcrun simctl launch --terminate-running-process booted \
  com.seungwoo.WayToYou -debugAccount mina

xcrun simctl launch --terminate-running-process booted \
  com.seungwoo.WayToYou -debugAccount sofia

xcrun simctl launch --terminate-running-process booted \
  com.seungwoo.WayToYou -debugAccount mina -debugReset YES

xcrun simctl launch --terminate-running-process booted \
  com.seungwoo.WayToYou -debugAccount mina -previewSheet us
```

`previewSheet`는 `compose`, `signal`, `keepsakes`, `us`, `letter`를 지원한다. 자세한 내용은 `docs/debug-simulator.md`에 있다.

## 8. 검증 환경과 명령

- 프로젝트: `WayToYou.xcodeproj`
- scheme: `WayToYou`
- bundle identifier: `com.seungwoo.WayToYou`
- Supabase Swift: `2.54.1`
- 현재 부팅된 시뮬레이터: iPhone 17, iOS 26.5
- 시뮬레이터 UUID: `C5919541-6BEA-4A25-92C7-939A469F18F7`
- 기본 실기기: `승우의 iPhone`
- 실기기 UUID: `06D7A8DA-E136-59E0-84EA-33DB46085EEE`
- 추가 실기기: `NXQOEKRJFJCMXM4`, iPhone 14 (`iPhone14,7`)
- iPhone 14 UUID: `D30BD3D7-C016-5256-A4BD-95F2BA16C751`
- 작업 완료 검증 기준은 계속 `승우의 iPhone`이며, 이번 도시 프로필 마커 빌드는 iPhone 14에도 설치·실행했다.

문서 작성 시점에 다음 Debug 시뮬레이터 빌드는 성공했다.

```bash
xcodebuild \
  -project WayToYou.xcodeproj \
  -scheme WayToYou \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  build
```

도시 프로필 마커 구현은 iPhone 17 시뮬레이터를 완전히 재실행한 뒤 화면을 건드리지 않은 상태에서 두 마커가 즉시 보이는 것까지 확인했다. `승우의 iPhone`과 `NXQOEKRJFJCMXM4` iPhone 14에도 같은 Debug 실기기 빌드를 설치하고 실행했다.

시뮬레이터 설치:

```bash
xcrun simctl install booted \
  /Users/seungwoo/Library/Developer/Xcode/DerivedData/WayToYou-ghkngftlsssqooeqtwfnpzxrlhxc/Build/Products/Debug-iphonesimulator/WayToYou.app
```

iOS 코드를 수정한 작업은 모두 끝낸 뒤 AGENTS 지침에 따라 `승우의 iPhone`에서 빌드·설치·실행한다. 문서만 수정한 경우에는 iOS 재실행이 필요하지 않다.

## 9. Git 이력 요약

현재 작업 브랜치의 주요 커밋은 아래 순서로 쌓였다.

| 커밋 | 내용 |
| --- | --- |
| `77fff7e` | Product Plan 문서 추가, 지구본 위도 제한 정리 |
| `fbe8518` | Swift 파일을 기능별 폴더로 정리 |
| `08f6f59` | 홈·간직함·우리 3탭 IA 적용 |
| `24e5d2d` | MapKit 도시·공항 온보딩 구현 |
| `d4ca3af` | UI 크롬을 흑백·중성으로 전환 |
| `3d6e1ce` | Ping을 Heart로 문서화 |
| `8801cb8` | Supabase CLI 프로젝트 연결 설정 |
| `0a41507` | 연타형 Heart Burst 구현 |
| `c3b7b35` | 레거시 테스트 사용자 초기화 migration |
| `2090df8` | 삭제된 사용자의 오래된 Keychain 세션 거부 |
| `67c9644` | Heart 액션 UI 단순화 |
| `17d996c` | 연결된 상대 간 Signal 구현 |
| `20d9c17` | 비공개 프로필 사진 Storage/RLS migration |
| `2b77877` | 프로필 사진 업로드·다운로드 클라이언트 |
| `550d8b6` | 고정 원형 마스크 크롭 구현 |
| `948d4b3` | 크롭 내비게이션을 기본 iOS 컨트롤로 변경 |
| `4663794` | 크롭을 native dark sheet로 표시 |
| `57cb5d3` | 크롭 sheet 배경 정리 |
| `65f3166` | 크롭 내비게이션을 검정으로 통일 |
| `58bb2e5` | 프로필 사진 성공 토스트 구현 |
| `b83b277` | 시뮬레이터 DEBUG 계정 2개 구현 |
| `5a7c8dd` | DEBUG 계정 문서화 |
| `0c4b3fb` | 진행 상태 문서 정리 |
| `ba6b9b6` | 도시 중심 프로필 마커와 동적 카메라 구현 |

중간 크롭 실험 커밋(`95b9607`, `fe5becf`, `f28826b`, `76aa126`)은 최종 형태로 가는 과정이다. 현재 HEAD의 코드를 기준으로 판단한다.

## 10. 다음 구현 순서

작업은 아래 순서를 권장한다. 도시 중심 프로필 마커는 완료됐으므로 첫 항목만 먼저 구현하고 검증·커밋한 뒤 다음으로 이동한다.

1. **마커 탭 시 이름 + 도시/국가만 보여주는 작은 정보 UI**
2. 두 도시를 잇는 절제된 Route 선
3. 최신 결정에 맞춰 프로필의 도시와 소포의 공항 책임 분리
4. 소포 작성 시 출발/도착 공항을 MapKit으로 선택하는 UX
5. 비행 중 Gift annotation과 배송 진행 상태
6. 실제 두 계정으로 Heart·Signal·프로필 사진 E2E 검증 및 수정
7. Parcel/Letter/Keepsakes 서버 모델과 상대 전송
8. Polaroid
9. Voice Tape
10. Interactive Widget
11. 익명 비행기와 Shared World

## 11. 다음 채팅 시작 체크리스트

```bash
cd /Users/seungwoo/Desktop/WayToYou
git status --short --branch
git log --oneline -12
sed -n '1,240p' docs/next-session-handoff.md
```

그 다음 `WayToYou/Features/Home/GlobeMapView.swift`의 annotation 선택 경로와 `ContentView.home`을 읽고 마커 정보 UI 한 단계만 구현한다.

작업 중 지켜야 할 것:

- 사용자 변경분과 무관한 파일을 되돌리지 않는다.
- 파일 검색은 `rg`/`rg --files`를 우선한다.
- 파일 수정은 `apply_patch`를 사용한다.
- 새 디자인 토큰을 만들지 않는다.
- 공항에 사람 프로필을 두지 않는다.
- 시뮬레이터 검증은 `mina`부터 시작한다.
- iOS 수정 완료 후 반드시 `승우의 iPhone`에서 실행한다.
- 성공한 범위만 커밋하고 다음 기능과 섞지 않는다.
