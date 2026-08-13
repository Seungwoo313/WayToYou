# Way to You 현재 진행상황

작성일: 2026-08-13
브랜치: `feature/globe-animation`
최신 기능 병합 기준: `d979b84` (`codex/minor-change` PR #4 병합 완료)
현재 작업 HEAD: `fd8c114` (`feature/globe-animation`)

다음 채팅에서 이어갈 구체적인 구현 범위와 최신 결정은 `docs/next-session-handoff.md`를 우선한다.

## 현재 방향

- 기존 사용자는 호환 대상으로 보지 않는다.
- 도시와 공항은 하드코딩하지 않고 MapKit을 기준으로 조회한다.
- 프로필 위치는 도시 중심에 두고, 공항은 한 번 저장하는 기본 배송값으로 분리한다.
- 소포는 기본 공항을 자동 적용하고 필요할 때만 바꾼 뒤 해당 배송 Route에 스냅샷으로 남긴다.
- 위치 권한은 사용자가 `현재 위치로 찾기`를 눌렀을 때만 요청한다.
- UI 크롬은 화이트·블랙·중성 그레이로 유지한다.
- 새로운 디자인 토큰 레이어는 추가하지 않는다.
- 실시간 채팅 대신 Heart, Signal, Letter, Parcel 같은 느린 연결 경험을 만든다.

## 상태 요약

| 영역 | 상태 | 비고 |
| --- | --- | --- |
| 파일 구조·탭 정보 구조 | 완료 | 코드 반영 완료 |
| MapKit 도시·공항 검색 | 구현 완료 | 프로필 도시·기본 배송 공항 책임 분리 완료 |
| 화이트·블랙 UI | 완료 | 실기기 검증 완료 |
| Apple·Google 인증·Keychain | 구현 완료 | 실제 provider·실기기 재검증 대기 |
| Heart | 구현 완료 | 실제 두 계정 E2E 검증 대기 |
| 연결된 Signal | RPC·수신 토스트·마커 스티커 구현 완료 | 실제 두 계정 양방향 E2E 검증 대기 |
| 프로필 사진 클라이언트 | 구현 완료 | 최신 실기기·상대방 표시 검증 대기 |
| 프로필 사진 Storage | 원격 마이그레이션 적용 완료 | 실제 상대방 권한 검증 대기 |
| 시뮬레이터 DEBUG 계정·도시 주입 | 완료 | 설정에서 즉시 변경하거나 실행 인자로 자동화 가능, 시뮬레이터 전용 |
| Supabase CLI | 연결·원격 동기화 완료 | 실제 두 계정 E2E 검증 대기 |
| MapKit 지구본 | 도시 프로필 마커·동적 카메라·근거리 확대·하강 애니메이션·도시 Route·뒷면 마커 완료 | 배송 Route·Gift annotation 미구현, 하강 중 타일 해상도 실기기 확인 대기 |
| 홈 도시 시계·날씨·설정 | 완료 | 시간·온도 단위와 Route Heart 설정 포함 |
| Device Presence·배터리 | 완료 | 두 실기기 publish·충전 전환·freshness 수동 QA 완료 |
| Letter·Delivery·Keepsakes | 로컬 데모 존재 | 서버 전송·제품 흐름 미구현 |
| Widget | 미착수 | 다음 Product Plan 단계 |

## 구현 완료 항목

### 기반 및 정보 구조 — 완료

- Swift 소스를 기능별 폴더로 정리했다.
- Product Plan 기준으로 탭을 `홈`, `간직함`, `우리`로 재편했다.
- 두 기능 브랜치의 작업은 GitHub PR #2, #3을 거쳐 `main`에 병합했다.

### MapKit 도시·기본 배송 공항 설정 — 구현 완료

- `RouteCity`와 `RouteAirport`를 서로 독립적인 값으로 분리했다.
- MapKit 지오코딩으로 도시를 검색한다.
- 현재 위치를 한 번 역지오코딩해 도시를 추천한다.
- 선택한 도시를 기준으로 MapKit 공항 POI를 검색해 기본 배송 공항으로 한 번 저장한다.
- 공항 이름·위치·식별자를 MapKit 결과에서 사용한다.
- 사용자가 직접 도시와 공항을 검색할 수 있다.
- 하드코딩 공항 목록은 사용하지 않는다.
- 위치 사용 목적을 `Info.plist`에 명시했다.
- 프로필·지구본은 도시만 사용하고 공항은 배송 기본값으로만 사용한다.
- `우리` 화면에서 나와 상대의 기본 공항을 확인하고 내 기본 공항을 수정할 수 있다.

주요 파일:

- `WayToYou/Core/Models/RoutePlaces.swift`
- `WayToYou/Services/RoutePlaceSearchService.swift`
- `WayToYou/Features/Connection/RouteCityPicker.swift`
- `WayToYou/Features/Connection/RouteAirportPicker.swift`
- `WayToYou/Features/Connection/ConnectionOnboardingView.swift`

관련 커밋:

- `8adffb3 refactor: separate profile city and default airport`
- `75afc5e copy: simplify airport change guidance`

### UI 방향 — 완료 · 실기기 검증 완료

- 전역 `Palette`를 블랙·화이트·중성 그레이로 변경했다.
- 기존 별빛/성운 배경의 푸른 색조를 제거했다.
- 콘텐츠 의미가 있는 소포 포장 색상은 유지했다.
- MapKit 선택 화면에 검색 로딩·빈 상태·오류 상태를 추가했다.
- MapKit 및 무채색 UI 버전은 `승우의 iPhone`에서 빌드·설치·실행했다.

주요 커밋:

- `24e5d2d feat: add MapKit route onboarding`
- `d4ca3af style: switch UI chrome to monochrome`

### MapKit 지구본·프로필 마커·도시 Route — 구현 완료

- 프로필은 공항이 아니라 사용자가 선택한 도시 중심 좌표에 표시한다.
- 두 도시의 구면 관계와 실제 하단 UI 여백으로 초기 시점을 계산하며 수동 카메라 좌표를 하드코딩하지 않는다.
- 최초 순서는 `connect → framing 요청 → marker sync 보류 → camera 확정 → CADisplayLink 두 프레임 → annotation 적용`이다.
- 이 순서는 화면을 건드리기 전 마커가 materialize되지 않던 MapKit 경합을 피하기 위해 유지한다.
- 마커 탭 시 spring/halo와 selection 햅틱을 재생한다. 지도 제스처 시작 시 선택을 닫으며 카메라는 유지한다.
- 큰 정보 카드와 도시/시간 pill은 시각 검토 후 제거했다.
- 이름·사진·Signal 갱신은 annotation view만 갱신하고 카메라 framing key에는 도시 좌표만 포함한다.
- 프로필 마커 앵커는 초기 근거리 확대 여부에 따라 나뉜다. 기본 전 지구 카메라를 유지하는 Route는 사진 아래의 흰 다리와 위치 점을 표시하고 점 중심을 도시 좌표에 고정한다. 근거리 확대가 실제로 확정된 Route는 다리와 점을 숨기고 46pt 원형 사진 중심을 도시 좌표에 맞춘다.
- 이 분기는 물리적 km가 아니라 기존 근거리 카메라의 최종 `zoomScale > 1` 판정을 그대로 사용한다. 사용자가 나중에 수동으로 확대·축소해도 최초 framing에서 정한 마커 형태는 바뀌지 않으며, 도시 조합이 바뀌어 새 framing을 요청할 때 초기화한다.
- 뒷면 화면 표현에는 실제 도시 좌표를 가리킬 수 있는 지표 앵커가 없으므로 항상 다리와 위치 점을 숨긴다. 같은 좌표 특수 케이스는 카메라를 확대하지 않고 두 annotation 전체를 68pt 간격으로 분리한다.
- 두 도시 중심은 `MKGeodesicPolyline`으로 연결해 지구 곡률을 따르는 최단 Route를 표시한다.
- Route는 얇은 반투명 흰색 점선이며 마커보다 아래에 그린다. 도시가 같으면 선을 표시하지 않는다.
- 도시가 바뀔 때만 overlay를 교체하며, 이름·사진·Signal·배터리 갱신은 Route와 카메라에 영향을 주지 않는다.
- 피렌체–웰링턴처럼 거의 대척점인 도시 조합은 MapKit의 최대 카메라 거리에서 실제 지표 annotation 두 개를 동시에 노출할 수 없다. 실제 annotation과 Route 좌표는 도시 중심에 그대로 두고, 가려진 쪽만 별도의 화면 표현으로 표시한다.
- 뒷면 표현은 `MKGeodesicPolyline`을 따라 배치한 투영 probe로 화면에 실제 렌더된 마지막 점선 위치를 찾는다. 다른 앞면 지역에 사람을 옮긴 것처럼 보이는 가짜 지도 좌표는 만들지 않는다.
- 마커 상태는 `실제 프로필 / 뒷면 원 / 완전 숨김`으로 구분한다. 뒷면 원은 실제 프로필보다 조금 작고 옅다. 일반 Route에서는 지평선 뒤 약 20°보다 깊어지면 실제 프로필과 뒷면 원을 모두 숨긴다.
- 지도 드래그·회전·확대와 관성 중에는 뒷면 원을 짧게 fade out하고 위치와 앞·뒤 상태를 갱신하지 않는다. 이동이 끝난 뒤 MapKit 투영이 안정되는 3 display frame을 기다려 최종 상태와 위치를 한 번 계산하고 fade in한다. 이 정책은 경계에서 프로필이 떨리는 현상을 막기 위한 의도된 UX다.
- 뒷면 표현은 지도 좌표 annotation이 아니라 `presentationOverlayView`의 화면 뷰다. 선택·접근성은 현재 보이는 표현 하나만 활성화하며, 실제 핀으로 돌아올 때도 fade in한다.
- 지구와 Route 끝 투영을 일치시키기 위해 pitch 제스처는 비활성화한다. 팬·핀치·회전과 관성은 MapKit 기본 동작을 유지한다.
- 기존 카메라 framing은 유지하고, 도시 간 각거리가 165°보다 크면서 Route가 거의 수평인 경우에만 준대척 fallback을 적용한다. 동거리 적도 중심을 구한 뒤 대권 중점 방향으로 20° 기울여 Route와 양 끝 표현을 확보하고, 이 경우에만 뒷면 허용 범위를 40°로 넓힌다.
- 각거리가 175°보다 크고 대권 중점이 극점에 걸리는 더 좁은 경우에는 중점에서 Route 위로 55° 이동해 극점 확대를 피하고 뒷면 허용 범위를 70°로 둔다. 나머지 잘 되던 조합은 기존 중심 계산과 20° 정책을 그대로 사용한다.
- 초기 전 지구 카메라와 annotation을 먼저 그대로 커밋한 뒤, 두 도시가 모두 앞면·화면 안에 있고 프로필 중심 간격이 50pt 미만이거나 Route Heart의 최대 heartbeat 크기가 어느 한 프로필과 4pt 여백을 확보하지 못할 때만 MapKit 카메라 거리로 확대한다.
- 확대는 프로필 중심 간격 236...248pt 이상을 목표로 하되 카메라 거리를 최소 3.35배 가까이 당기고 Route의 구면 중점으로 중심을 옮긴다. 작은 화면·가로 화면에서는 Route 방향과 68×92pt 프로필 전체 캔버스를 기준으로 확대 상한을 자동 제한한다. 반쯤 잘린 큰 지구나 잘린 끝점 없이 확실한 지역 뷰까지 들어간다. Heart 설정을 나중에 켜도 카메라가 움직이지 않도록 초기 framing에서 공간을 항상 예약한다.
- 이 조건을 통과하지 않으면 두 번째 카메라 호출 자체를 하지 않으므로 기존 정상·장거리·준대척 화면은 그대로 유지한다. 같은 좌표는 카메라를 유지하고 68pt 간격의 접근 가능한 프로필 한 쌍으로 표시한다.
- annotation 커밋 뒤 2 display frame 후 확대한다. MapKit 기본 애니메이션 대신 `CADisplayLink`로 카메라를 매 프레임 직접 그려 전 지구에서 지역으로 내려간다. 기본 애니메이션은 카메라 거리를 선형으로 줄이는데, 체감 확대 속도는 거리의 로그 변화율이라 앞부분이 멈춘 듯 보이다가 마지막에 꽂힌다. 거리는 기하 보간하고 중심은 대권 slerp로 옮기며, 속도는 가속 0.10 · 감속 0.45의 비대칭 사다리꼴을 쓴다. 지속 시간은 `clamp(0.95 + 0.62 × ln(배율), 1.0, 2.4)`초로 배율에 따라 늘어나 어떤 도시 조합에서도 체감 속도가 같다. 원리와 함정은 `docs/camera-dive-animation.md`에 따로 정리했다.
- 하강 중에는 마커 분류를 얼린다. 최대 257개 투영 probe의 화면 좌표가 매 프레임 바뀌어, 한 프레임만 잘못 읽어도 보이는 도시가 뒷면으로 판정되어 아바타가 사라진다. 프로필은 실제 annotation이라 MapKit이 재투영한다.
- 마커 다리는 순간 전환이 아니라 하강의 5%...42% 구간에서 분수값으로 접힌다. 점은 도시 좌표에 고정된 채 줄기만 짧아지고 아바타가 그 위로 내려앉는다. 기존 42pt 앵커 점프는 원래 있었으나 빠른 애니메이션에 가려져 있었다.
- Reduce Motion에서는 하강 없이 같은 최종 카메라를 적용한다. 대기 중이나 하강 중에 지도 제스처가 시작되면 카메라를 즉시 사용자에게 넘기고, 도시 조합이 바뀌면 하강을 취소한다.
- iPhone 17 / iOS 26.5에서 0...19,614km의 거리·투영 조합 25개를 동일 입력 Before / After로 캡처했다. 18개는 확실한 지역 뷰로 확대되고 7개는 기존 지구본을 유지했다. New York – Miami는 Route Heart를 실제로 켠 화면에서도 충돌하지 않는 것을 별도로 확인했다. 준대척 문제 8개와 정상 5개도 변경 전·후 동일 입력으로 재검증했다. 비교표는 `artifacts/debug-city-tests/nearby-framing-comparison.md`에 있다.

관련 커밋:

- `ba6b9b6 feat: add city profile markers`
- `c35972f feat: add interactive profile marker details`
- `8367f0a feat: refine globe signal markers and notifications`
- `1d9defc feat: add city route line`
- `21210a9 feat: add globe backside route marker`
- `3c4ffa6 fix: stabilize backside globe markers`
- `0182240 fix: frame near-antipodal globe routes`
- `62b2df9 Add adaptive nearby city framing`
- `a6d5be9 Restore globe marker legs by framing mode`
- `fd8c114 Dive into the globe instead of snapping to the region`

### 홈 도시 정보·설정·Route Heart — 구현 완료

- 홈 양쪽에 각 도시의 현지 시각과 현재 날씨를 표시한다.
- 시간 표기 방식과 온도 단위, Route Heart 표시·애니메이션·이모지를 설정에서 바꿀 수 있다.
- Route Heart 설정 변경은 지구 카메라 framing이나 Route 좌표를 바꾸지 않는다.
- 홈 크롬과 숫자 없는 배터리 아이콘을 현재 흑백·중성 방향에 맞게 다듬었다.

관련 커밋:

- `67b9841 feat: add city clocks weather and settings`
- `3649818 style: refine home chrome and battery indicator`
- `c763ace feat: add configurable route heart animation`

### Heart / 인증 상태 — 구현 완료 · 최신 실기기 검증 대기

- Ping 명칭을 Heart 중심 상호작용으로 정리했다.
- realtime-style Heart burst 오버레이와 액션 흐름을 추가했다.
- Heart 컨트롤을 단순화했다.
- 오래된 Keychain 인증 세션을 거부하도록 수정했다.
- 기존 레거시 테스트 사용자 데이터를 초기화했다.

관련 커밋:

- `3d6e1ce docs: rename Ping interaction to Heart`
- `0a41507 feat: add realtime-style Heart bursts`
- `c3b7b35 chore: reset legacy test users`
- `2090df8 fix: reject stale Keychain auth sessions`
- `67c9644 style: simplify Heart action controls`

### Signal — 구현 완료 · 양방향 E2E 검증 대기

- 연결된 상대에게 보이는 현재 상태 Signal 흐름을 추가했다.
- Signal 보내기·목록 조회를 Supabase security-definer RPC 경계로 연결했다.
- Signal 타입과 만료/최근 상태 모델을 정리했다.
- 관련 DB 마이그레이션을 추가했다.
- Signal 선택 화면과 홈 액션은 컬러 유니코드 이모지를 사용한다.
- 새 incoming Signal만 `이모지 + 상대 이름 + 경과 시간`의 작은 토스트로 약 3초 표시한다.
- 앱 시작의 최초 목록 동기화에서는 과거 Signal 토스트를 재생하지 않는다.
- 내/상대 프로필 마커에는 각 outgoing/incoming 최신 Signal을 이모지 스티커로 표시한다.
- 마커 이모지는 원 배경 없이 실제 알파 외곽을 따라 1.5pt 흰 테두리를 만들며, 범용 렌더러가 어떤 유니코드 이모지든 기본 15pt로 처리하고 캐시한다.

관련 커밋:

- `17d996c feat: add connected Signal states`
- `8367f0a feat: refine globe signal markers and notifications`

### 프로필 사진 보안 저장소 — 원격 적용 완료 · E2E 검증 대기

- 비공개 Supabase Storage bucket 마이그레이션을 추가했다.
- 사진은 소유자와 현재 연결된 상대만 읽을 수 있도록 Storage 정책을 정의했다.
- 프로필에 `avatar_path`, `avatar_updated_at` 필드를 추가하는 SQL을 준비했다.
- 실제 업로드·다운로드 UI는 별도 클라이언트 흐름에서 구현했다.

관련 커밋:

- `20d9c17 feat: add secure profile photo storage`

### 프로필 사진 클라이언트 흐름 — 구현 완료 · 실기기 검증 대기

- 사진 라이브러리와 카메라에서 프로필 사진을 선택할 수 있다.
- 고정 마스크 안에서 사진을 확대·이동해 크롭할 수 있다.
- 네이티브 다크 시트와 iOS 내비게이션 컨트롤을 사용한다.
- JPEG로 처리한 사진을 Supabase Storage에 업로드한다.
- 온보딩과 `우리` 화면에서 프로필 사진을 표시한다.
- 업로드 성공 시 `우리` 화면에 애니메이션 토스트를 표시한다.
- 크롭 시트 내비게이션은 검은색 네이티브 스타일로 유지한다.
- 최신 아바타 흐름은 아직 `승우의 iPhone`에서 재검증해야 한다.

관련 커밋:

- `2b77877 feat: add profile photo uploads`
- `95b9607 feat: add interactive profile photo crop`
- `f28826b refactor: remove profile photo crop flow`
- `550d8b6 feat: add fixed-mask profile photo crop`
- `76aa126 fix: center profile photo crop layout`
- `948d4b3 fix: use native crop navigation controls`
- `4663794 style: present avatar crop in native dark sheet`
- `57cb5d3 style: refine avatar crop sheet background`
- `65f3166 style: use black avatar crop navigation`
- `58bb2e5 feat: add animated avatar success toast`

### 시뮬레이터 DEBUG 계정·프로그래밍 가능한 도시 테스트 — 완료 · 시뮬레이터 전용

- Supabase 로그인과 온보딩 없이 연결된 화면으로 진입할 수 있는 시뮬레이터 전용 계정을 추가했다.
- `mina`는 서울·인천공항, `sofia`는 Paris·CDG fixture를 사용한다.
- 두 공항 값은 실제 앱 검색 데이터가 아니라 `#if DEBUG` 시뮬레이터 테스트 fixture다.
- Heart, Signal, Parcel, 프로필 사진 변경을 역할별 로컬 상태로 반복 검증할 수 있다.
- DEBUG 설정의 `내 테스트 도시`와 `상대 테스트 도시`에서 MapKit 검색 결과를 고르면 앱을 다시 빌드하지 않고 홈의 도시·거리·시차·날씨가 즉시 바뀐다.
- 자동 캡처에서는 `WTY_DEBUG_MY_CITY_JSON`, `WTY_DEBUG_PARTNER_CITY_JSON` 환경변수로 임의 도시의 이름·국가·좌표·시간대를 주입할 수 있다.
- `scripts/capture-debug-home.sh`가 시뮬레이터 재실행, 도시 주입, 홈 대기, PNG 캡처를 한 명령으로 수행한다.
- 실기기·Release 빌드와 실제 Supabase 상대방 동기화에는 사용하지 않는다.

관련 파일:

- `WayToYou/Core/Debug/DebugAccount.swift`
- `WayToYou/Core/Debug/DebugCityTarget.swift`
- `scripts/capture-debug-home.sh`
- `docs/debug-simulator.md`

관련 커밋:

- `b83b277 feat: add simulator debug accounts`
- `6213463 feat: add programmable debug city testing`

### Device Presence·배터리 바 — 원격 적용·실기기 publish 확인

2026-08-12에 데이터·보안 → monitor → UI 순서로 구현하고 원격 DB와 두 실기기까지 연결했다.

- `supabase/migrations/20260811223000_device_presence.sql`: `wty_device_presence` 테이블과 `wty_set_device_presence` / `wty_get_partner_presence` / `wty_clear_device_presence` security-definer RPC. 행은 `(connection_id, user_id)` membership FK에 묶이고 연결 해제 시 cascade 삭제된다. 현재 연결 상대만 읽을 수 있으며 클라이언트는 user id·connection id·timestamp를 지정할 수 없다.
- 서버 set RPC는 상태·퍼센트·연결 변경은 즉시 저장하고 동일 값의 timestamp 갱신은 5분 간격으로 제한한다. 클라이언트 throttle만 우회해 쓰는 경로를 막았다.
- `WayToYou/Services/DeviceBatteryMonitor.swift`(신규): foreground·연결 상태 동안만 UIDevice 배터리를 관찰하고 unknown(-1)은 내보내지 않는다. 다른 코드가 이미 battery monitoring을 켠 경우 stop에서 임의로 끄지 않는다.
- `WayToYouStore`: transient `myDevicePresence`/`partnerDevicePresence`, 상태 변화 즉시 publish·같은 값 5분 주기 갱신, 사용자·연결 ID 전환 시 presence와 throttle 상태 초기화.
- `ContentView`: `presence` task가 monitor 시작/중지와 30초 주기 상대 동기화를 담당한다.
- `GlobeMapView`: 프로필 마커 바로 위에 숫자 없이 작은 배터리 아이콘만 표시한다. 위성 지도에서의 대비를 위해 아이콘 크기의 반투명 검정 배경을 유지하며, 충전 시 초록+번개, 약 20% 이하에서는 빨강으로 표시한다. freshness는 10분 이후 muted, 60분 이후 숨김. 배터리 갱신은 annotation만 갱신하며 카메라 framing key에 포함하지 않는다.
- DEBUG 시뮬레이터 계정은 상대 fixture(미나→Sofia 62% 방전, Sofia→미나 87% 충전)로 UI만 검증한다.

검증 결과:

- `supabase db push`로 원격 migration 적용 완료. 이후 `migration list`의 local/remote 8개 version이 일치하고 dry-run은 `Remote database is up to date.`다.
- anon role의 partner RPC·clear RPC·테이블 직접 SELECT는 모두 HTTP 401로 거부됐다.
- iPhone 17 시뮬레이터에서 62% 방전과 87% 충전 fixture UI를 확인했다.
- `승우의 iPhone`과 iPhone 14에 빌드·설치·실행했다. 두 앱 실행 뒤 원격 `wty_device_presence` 예상 행 수가 2개여서 두 실제 계정의 publish 성공을 확인했다.
- 숫자를 제거한 최종 배터리 아이콘 UI도 시뮬레이터에서 확인한 뒤 두 실기기에 다시 설치·실행했다.

두 화면의 상대 값, 충전 케이블 연결·해제, freshness와 unknown 처리를 포함한 수동 QA를 완료했다. clear RPC와 store 경로는 있으나 사용자가 배터리 공유를 끄는 설정 UI는 아직 없다.

관련 커밋:

- `79d6431 feat: add secure battery presence`

## Supabase 상태 — CLI 연결·원격 DB 적용 완료

- Supabase Swift SDK와 앱 API 연결은 기존 설정으로 구성되어 있다.
- Supabase CLI를 설치하고 `supabase init`을 실행했다.
- 프로젝트 연결을 완료했다.
- `supabase/config.toml`과 `supabase/.gitignore`를 저장소에 추가했다.
- CLI 로그인은 완료했다.

관련 파일:

- `supabase/config.toml`
- `supabase/migrations/20260810194000_secure_partner_connections.sql`
- `supabase/migrations/20260811171000_mapkit_route_endpoints.sql`
- `supabase/migrations/20260811174000_hearts.sql`
- `supabase/migrations/20260811180500_reset_test_users.sql`
- `supabase/migrations/20260811190000_signals.sql`
- `supabase/migrations/20260811193000_profile_photos.sql`
- `supabase/migrations/20260811223000_device_presence.sql`
- `supabase/migrations/20260812132000_profile_city_default_airport.sql`
- `WayToYou/Services/SupabaseConnectionService.swift`

2026-08-12에 다음 명령으로 원격 상태를 확인했다.

```bash
supabase migration list
supabase db push --dry-run
```

- 8개 로컬 migration이 모두 같은 version으로 원격에 적용돼 있다.
- `db push --dry-run` 결과는 `Remote database is up to date.`다.
- `wty_device_presence` 테이블과 primary/connection index가 원격에 존재한다.
- linked DB lint 결과는 `No schema errors found`다.
- migration 적용과 실제 앱 E2E 검증은 별개다.
- Apple·Google 로그인, 두 실제 계정 연결, Heart·Signal 송수신, 상대 프로필 사진 다운로드 권한은 아직 다시 확인해야 한다.
- 이후 이력이 어긋나면 `migration repair`를 바로 실행하지 말고 원인을 먼저 확인한다.

## 다음 작업 순서 — 대기 및 미착수

1. 소포 작성 시 양쪽 기본 공항 자동 적용·필요 시 변경·배송 Route 스냅샷 저장
2. 프로필 저장·복원과 비공개 상대 사진 표시 end-to-end 검증
3. 최신 Heart·Signal 흐름을 실제 두 계정에서 통제된 절차로 재검증
4. Letter·Parcel·Delivery·Keepsakes 서버 흐름 구현
5. Widget 및 후속 Product Plan 기능 구현

## 검증 메모

- 작업 중인 앱: `com.seungwoo.WayToYou`
- 실기기: `승우의 iPhone`
- 변경 후 iOS 작업은 실기기 실행까지 확인한다.
- MapKit 온보딩과 무채색 UI 버전은 실기기에서 확인했다.
- 최신 Signal·마커 UI는 `승우의 iPhone`과 iPhone 14에 빌드·설치·실행했다. 양방향 송수신·만료를 통제된 절차로 검증하는 작업은 남아 있다.
- 도시 Route 점선은 iPhone 17 시뮬레이터에서 서울–파리 두 마커를 정확히 연결하고 초기 화면에 즉시 나타나는 것을 확인한 뒤 `승우의 iPhone`에 빌드·설치·실행했다.
- 준대척 도시 뒷면 마커와 드래그 중 fade 정책은 `승우의 iPhone`과 iPhone 14에 빌드·설치·실행했다. 피렌체–웰링턴 조합에서 경계 근처 실시간 추적을 제거하고, 관성 종료 뒤 최종 위치를 한 번 갱신하도록 확인했다.
- 프로필 도시·기본 배송 공항 분리는 iPhone 17 시뮬레이터의 `우리` 화면에서 `서울 ↔ Paris`와 `ICN ↔ CDG`가 별도 정보로 표시되는 것을 확인한 뒤 `승우의 iPhone`과 iPhone 14에 빌드·설치·실행했다.
- 최신 프로필 사진 선택·크롭·업로드 변경분도 다음 실기기 빌드에서 재검증해야 한다.
- DEBUG 계정 흐름은 시뮬레이터 전용 검증 경로로 문서화했다.
- 프로그래밍 가능한 도시 주입으로 준대척 문제 조합 8개와 기존 정상 조합 5개를 iPhone 17 시뮬레이터에서 다시 캡처했다. 최종 결과와 중간 실험 이미지 50장은 `artifacts/debug-city-tests/png/` 한 폴더에 단계 접두어를 붙여 보관한다.
- 근거리 카메라는 같은 시뮬레이터에서 도시 조합 25개의 Before / After 50장과 동일 입력 준대척 회귀 26장을 캡처했다. 준대척 지도 영역의 변경 전·후 평균 RGB 절대 오차는 0.55...2.72 / 255였다.
- 근거리 카메라 최종 변경분은 Debug 시뮬레이터와 Release 실기기 빌드에 성공했고 `승우의 iPhone`에 설치·실행했다. 실행 뒤 기기에서 `WayToYou` 프로세스가 유지되는 것도 확인했다.
- `a6d5be9`의 framing별 마커 다리 분기는 Debug iPhone 17 시뮬레이터와 Release 실기기 빌드에 성공했다. `승우의 iPhone`에 설치·실행한 뒤 `WayToYou` 프로세스 유지도 확인했다.
- `0182240`의 최종 카메라 변경은 Debug 시뮬레이터 검증 뒤 Release 구성으로 빌드하고 `승우의 iPhone`에 설치·실행했다.
- 8개 Supabase migration은 원격과 일치하고 dry-run 기준 추가 적용 항목이 없다.
- 두 실기기 실행 후 원격 Device Presence 행 2개를 확인했고 충전 전환·freshness 수동 QA도 완료했다.
- 앱 인증 토큰은 iOS Keychain을 사용하며, Keychain은 Supabase DB가 아니라 기기 내부의 보호된 인증 저장소다.
- 최신 기능 병합 기준은 `d979b84`이고, 현재 `feature/globe-animation`의 작업 HEAD는 `fd8c114`다.
