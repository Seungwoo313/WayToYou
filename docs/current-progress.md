# Way to You 현재 진행상황

작성일: 2026-08-11
브랜치: `codex/product-plan-mvp`
최신 커밋: `67c9644 style: simplify Heart action controls`

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
- `WayToYou/Services/SupabaseConnectionService.swift`

### 아직 하지 않은 것

- `supabase db push`는 아직 실행하지 않았다.
- 원격 DB의 실제 마이그레이션 적용 상태는 아직 확인하지 않았다.
- 따라서 원격 DB에 `route_endpoint` 컬럼과 `wty_save_profile(text, jsonb)` 함수가 존재한다고 가정하면 안 된다.
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
4. Signal의 서버 송수신 및 만료 상태 연결
5. Letter·Parcel·Delivery·Archive 흐름 구현
6. Widget 및 후속 Product Plan 기능 구현

## 검증 메모

- 작업 중인 앱: `com.seungwoo.WayToYou`
- 실기기: `승우의 iPhone`
- 변경 후 iOS 작업은 실기기 실행까지 확인한다.
- 앱 인증 토큰은 iOS Keychain을 사용하며, Keychain은 Supabase DB가 아니라 기기 내부의 보호된 인증 저장소다.
