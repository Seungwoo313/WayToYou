# Way to You 현재 진행상황

작성일: 2026-08-11
브랜치: `codex/product-plan-mvp`
최신 커밋: `58bb2e5 feat: add animated avatar success toast`

## 현재 방향

- 기존 사용자는 호환 대상으로 보지 않는다.
- 도시와 공항은 하드코딩하지 않고 MapKit을 기준으로 조회한다.
- 위치 권한은 사용자가 `현재 위치로 찾기`를 눌렀을 때만 요청한다.
- UI 크롬은 화이트·블랙·중성 그레이로 유지한다.
- 새로운 디자인 토큰 레이어는 추가하지 않는다.
- 실시간 채팅 대신 Heart, Signal, Letter, Parcel 같은 느린 연결 경험을 만든다.

## 완료된 구현

### 기반 및 정보 구조

- Swift 소스를 기능별 폴더로 정리했다.
- Product Plan 기준으로 탭을 `홈`, `간직함`, `우리`로 재편했다.
- Git 브랜치 `codex/product-plan-mvp`에서 작업 중이다.

### MapKit 도시·공항 온보딩

- `RouteCity`, `RouteAirport`, `RouteEndpoint`, `CoupleRoute` 모델을 추가했다.
- MapKit 지오코딩으로 도시를 검색한다.
- 현재 위치를 한 번 역지오코딩해 도시를 추천한다.
- 해당 도시를 기준으로 MapKit 공항 POI를 검색한다.
- 공항 이름·위치·식별자를 MapKit 결과에서 사용한다.
- 사용자가 직접 도시와 공항을 검색할 수 있다.
- 하드코딩 공항 목록은 사용하지 않는다.
- 위치 사용 목적을 `Info.plist`에 명시했다.

주요 파일:

- `WayToYou/Core/Models/RouteEndpoint.swift`
- `WayToYou/Services/RoutePlaceSearchService.swift`
- `WayToYou/Features/Connection/RouteEndpointPicker.swift`
- `WayToYou/Features/Connection/ConnectionOnboardingView.swift`

### UI 방향

- 전역 `Palette`를 블랙·화이트·중성 그레이로 변경했다.
- 기존 별빛/성운 배경의 푸른 색조를 제거했다.
- 콘텐츠 의미가 있는 소포 포장 색상은 유지했다.
- MapKit 선택 화면에 검색 로딩·빈 상태·오류 상태를 추가했다.
- MapKit 및 무채색 UI 버전은 `승우의 iPhone`에서 빌드·설치·실행했다.

주요 커밋:

- `24e5d2d feat: add MapKit route onboarding`
- `d4ca3af style: switch UI chrome to monochrome`

### Heart / 인증 상태

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

### Signal

- 연결된 상대에게 보이는 현재 상태 Signal 흐름을 추가했다.
- Signal 보내기·목록 조회를 Supabase security-definer RPC 경계로 연결했다.
- Signal 타입과 만료/최근 상태 모델을 정리했다.
- 관련 DB 마이그레이션을 추가했다.

관련 커밋:

- `17d996c feat: add connected Signal states`

### 프로필 사진 보안 저장소

- 비공개 Supabase Storage bucket 마이그레이션을 추가했다.
- 사진은 소유자와 현재 연결된 상대만 읽을 수 있도록 Storage 정책을 정의했다.
- 프로필에 `avatar_path`, `avatar_updated_at` 필드를 추가하는 SQL을 준비했다.
- 아직 앱의 사진 선택·업로드 UI는 구현하지 않았다.

관련 커밋:

- `20d9c17 feat: add secure profile photo storage`

### 프로필 사진 클라이언트 흐름

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

## Supabase 상태

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
- `WayToYou/Services/SupabaseConnectionService.swift`

### 아직 하지 않은 것

- `supabase db push`는 아직 실행하지 않았다.
- 원격 DB의 실제 마이그레이션 적용 상태는 아직 확인하지 않았다.
- 따라서 원격 DB에 `route_endpoint` 컬럼과 `wty_save_profile(text, jsonb)` 함수가 존재한다고 가정하면 안 된다.
- Heart 테이블/RPC와 테스트 사용자 초기화 마이그레이션도 원격 DB에 적용됐다고 가정하면 안 된다.
- Signal 테이블/RPC와 프로필 사진 Storage 정책도 원격 DB에 적용됐다고 가정하면 안 된다.
- 프로필 저장의 서버 연동을 확인하려면 먼저 `migration list`와 `db push --dry-run`을 실행해야 한다.

다음 확인 순서:

```bash
supabase migration list
supabase db push --dry-run
supabase db push
```

`migration list`에서 기존 원격 이력과 로컬 파일이 어긋나면 `migration repair`를 바로 실행하지 말고 원인을 먼저 확인한다.

## 다음 작업 순서

1. 다른 작업공간에서 Supabase 마이그레이션 상태 확인 및 필요 시 적용
2. 원격 DB 적용 후 프로필 저장·복원 end-to-end 검증
3. 최신 Heart 흐름을 `승우의 iPhone`에서 재검증
4. 최신 프로필 사진 크롭·업로드 흐름을 `승우의 iPhone`에서 검증
5. 프로필 사진 비공개 다운로드와 상대방 표시 end-to-end 검증
6. Letter·Parcel·Delivery·Archive 흐름 구현
7. Widget 및 후속 Product Plan 기능 구현

## 검증 메모

- 작업 중인 앱: `com.seungwoo.WayToYou`
- 실기기: `승우의 iPhone`
- 변경 후 iOS 작업은 실기기 실행까지 확인한다.
- MapKit 온보딩과 무채색 UI 버전은 실기기에서 확인했다.
- 최신 Signal Swift 변경분은 다음 실기기 빌드에서 재검증해야 한다.
- 최신 프로필 사진 선택·크롭·업로드 변경분도 다음 실기기 빌드에서 재검증해야 한다.
- 앱 인증 토큰은 iOS Keychain을 사용하며, Keychain은 Supabase DB가 아니라 기기 내부의 보호된 인증 저장소다.
