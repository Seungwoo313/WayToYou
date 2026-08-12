# Way to You — Product Plan v2

> **Some things are worth waiting for.**  
> 빠르게 소비되는 메시지 대신, 천천히 보내고 오래 간직하는 마음을 위한 iOS 앱.

---

## 1. Product Positioning

### 한 문장 정의

**Way to You는 비행기를 타야 만나게 되는 커플이, 떨어져 있는 동안 작은 신호와 느린 디지털 선물을 주고받는 앱이다.**

핵심은 채팅이 아니다.

카카오톡, iMessage, WhatsApp이 잘하는 것은:
- 빠른 대화
- 즉각적인 전송
- 실시간 반응

Way to You가 만들려는 것은:
- 말하지 않는 시간에도 느껴지는 상대의 존재
- 답장을 요구하지 않는 작은 신호
- 천천히 보내고 기다리는 경험
- 시간이 지나도 다시 꺼내볼 수 있는 디지털 물건
- 둘 사이의 거리를 하나의 감정적 경험으로 바꾸는 것

---

## 2. Core Insight

인스턴트 메신저는 빠르고 편리하지만, 대부분의 메시지는 다음처럼 소비된다.

`보냄 → 즉시 도착 → 읽음 → 답장 → 묻힘`

Way to You는 반대로 간다.

`만듦 → 담아둠 → 보냄 → 이동함 → 기다림 → 도착 → 열어봄 → 남음`

### 핵심 철학

> **No instant chat.**

짧은 실시간 텍스트 대화는 만들지 않는다.

- 짧은 애정 표현 → `Heart`
- 현재 상태 표현 → `Signal`
- 긴 마음 → `Letter`
- 목소리 → `Voice Tape`
- 한 순간 → `Polaroid`
- 여러 기억 → `Box`

즉, 메시지를 더 많이 보내는 앱이 아니라 **적게 보내더라도 더 오래 남게 만드는 앱**이다.

---

## 3. Target

### Primary Target

**Plane-distance couples**

즉:
- 서로 만나기 위해 비행기를 타는 커플
- 국제 장거리 커플
- 국내라도 항공 이동이 자연스러운 커플
- 서로의 공항이 관계에서 의미 있는 커플

예:
- Seoul ↔ New York
- Seoul ↔ Firenze
- Seoul ↔ Jeju
- Tokyo ↔ Sapporo
- Paris ↔ London

### 왜 이 타깃인가

공항은 장거리 커플에게 단순한 교통시설이 아니다.

- 만나러 가는 장소
- 다시 헤어지는 장소
- 기다리는 장소
- 재회의 장소

Way to You는 이 감정을 제품의 중심 상징으로 쓴다.

---

## 4. Onboarding

온보딩은 짧고 감정적으로 설계한다.

### Step 1 — Your City

> **Where do you live?**

예:
- Seoul, South Korea
- Firenze, Italy

사용자가 도시를 입력한다.

### Step 2 — Partner Connection

상대를 초대한다.

상대방도 자신의 도시를 선택한다.

### Step 3 — Your Cities

둘이 연결되면 앱이 두 사람을 각 도시 중심의 프로필 마커로 보여준다.

예:

`Seoul ↔ Firenze`

카피:

> **Our Cities**

공항은 사람의 프로필 위치가 아니라 **기본 배송 공항**으로 한 번 설정한다. 이후 Letter·Gift·Parcel 작성 시 내 공항과 상대 공항을 자동으로 채우고, 필요한 배송에서만 변경한다. 실제로 보낼 때 선택된 두 공항은 그 배송의 Route 스냅샷으로 저장한다.

배송별 Route가:
- Gift Delivery
- Air Mail
- Keepsakes의 당시 이동 기록
- 수하물 태그

의 기준이 된다.

---

## 5. Location Philosophy

Way to You는 실시간 위치 추적 앱이 아니다.

### 사용하지 않는 것

- 실시간 GPS 추적
- 상대 현재 위치
- 마지막 위치
- 이동 경로 추적
- 백그라운드 위치 감시

### 사용하는 것

- 사용자가 선택한 도시
- 각 사용자가 한 번 설정하고 필요할 때 수정하는 기본 배송 공항
- 소포를 보낼 때 기본값에서 필요하면 변경한 출발·도착 공항
- 각 배송에 저장되는 Route

즉:

> **사람을 추적하지 않고, 두 도시와 마음이 이동하는 Route를 보여준다.**

---

# 6. Core Interaction Model

Way to You의 표현 강도는 세 단계로 나뉜다.

`Heart → Signal → Gift`

## 6.1 Heart

가장 가벼운 표현.

목적:

> “그냥 네 생각났어.”

UI:

`♥`

누를 때마다 하트가 화면 위로 떠오른다. 짧은 시간 동안 연속으로 누른 하트는 하나의 `Heart Burst`로 묶고, 상대 화면에서는 같은 개수만큼 순서대로 재생한다.

특징:
- 텍스트 없음
- 매 탭 즉시 로컬 애니메이션과 가벼운 햅틱
- 연타 횟수는 하나의 Burst로 묶어 전송
- 받은 Burst는 원래 횟수대로 하트를 재생
- 읽음 표시 없음
- 답장 의무 없음
- 대화창 없음
- 상대도 Heart로 되돌려줄 수 있음

## 6.2 Signal

Signal은 삐삐 / 무전기 감성으로 만든다.

목적:

> “나 지금 이런 상태야.”

예:
- 😴 Sleeping
- 💻 Focusing
- ☕ Free
- 🚶 Out
- 🏠 Resting

### 앱 안의 표현

- Signal 선택과 홈 액션은 컬러 유니코드 이모지를 사용한다.
- 내/상대의 최신 Signal은 각 도시 프로필 마커의 모서리에 작은 이모지 스티커로 표시한다.
- 원형 배경 대신 이모지 실제 외곽을 따라 얇은 흰 테두리를 두어 위성 지도에서도 읽히게 한다.
- 새 Signal을 받으면 `☕️ 승우 · 3분 전`처럼 이모지·이름·상대 시간만 담은 작은 토스트를 잠시 표시한다.
- 상대 상태를 설명하는 큰 지속 카드나 온라인·마지막 접속 UI는 사용하지 않는다.

### 핵심 UX

위젯에서 한 번 탭.

```text
┌─────────────────────┐
│ Sofia        2:18 PM│
│                     │
│       ☕             │
│                     │
│ 🌙   💻   ☕   ♡    │
└─────────────────────┘
```

앱을 열 필요 없이 Signal을 보낸다.

### 복고 통신기 디자인

- 작은 LINK 표시
- LED
- 모노스페이스 숫자
- 물리 버튼 느낌
- 짧은 삐 소리
- `SIGNAL SENT`
- `SIGNAL RECEIVED`

### Signal 원칙

Signal은 감시 기능이 아니다.

- 자동 상태 감지 없음
- 온라인 표시 없음
- 마지막 접속 없음
- 일정 시간이 지나면 자동 만료

---

# 7. Gifts

Gift는 첨부파일이 아니라 **디지털 물건**이어야 한다.

## 7.1 Polaroid

일반 사진 공유가 아니라 “한 순간”을 보낸다.

아이디어:
- Gift Camera
- 과도한 편집 제한
- 한 장 중심
- 상대가 받으면 바로 선명하게 보이지 않음
- 천천히 현상되는 연출
- 짧은 손글씨 추가 가능

목표:

> 사진을 많이 보내는 것이 아니라, 한 장을 골라 남기는 것.

## 7.2 Letter

짧은 텍스트 대신 진짜 편지를 쓴다.

특징:
- 제목
- 긴 글
- 중간 저장
- 며칠에 걸쳐 이어쓰기 가능
- 사진 소수 첨부
- 완성 후 봉투에 넣기
- 보낸 후에는 수정하지 않는 방향

핵심:

> 채팅이 아니라 하나의 완성된 편지.

## 7.3 Voice Tape

복고 컨셉을 가장 강하게 가져가는 기능.

일반 음성 메시지가 아니라 **카세트테이프**를 녹음해서 보낸다.

### Recording UI

- 카세트 외형
- REC 버튼
- `딸깍` 햅틱
- 릴 회전
- 왼쪽 릴 감소 / 오른쪽 릴 증가
- waveform 중심 UI는 피함
- 말실수와 침묵도 그대로 남기는 방향

### Playback UI

상대가 받은 Tape을 플레이어에 넣는다.

`◀◀  ▶  ■`

- Play
- Stop
- Rewind

## 7.4 Touch

상대의 손길을 디지털로 보낸다.

보내는 사람이:
- 탭
- 길게 누르기
- 원
- 하트

등을 그리면 위치, 타이밍, 속도를 기록한다.

받는 사람은 손가락을 화면에 올리고 Core Haptics로 상대의 패턴을 느낀다.


## 7.5 Box

여러 Gift를 하나의 소포에 담는 기능.

예:
- Polaroid
- Voice Tape
- Letter
- Touch
- Ticket

중요:

Box는 매일 보내는 기능이 아니다.

월요일에 Polaroid 하나,
수요일에 Voice Tape 하나,
금요일에 Letter 하나를 넣고 그날 보낼 수도 있다.

```text
A box for Sofia

[ Polaroid ] [ Voice Tape ]
[ Letter    ]

3 things inside

+ Add something

Seal the box
```

---

# 8. Delivery / Air Mail

Gift를 보내는 순간부터 “전송”이 아니라 “여행”이 시작된다.

Route:

`ICN → FLR`

### 일반 Gift

짧은 배송 연출.

`Gift → 포장 → 태그 → 출발`

약 1~2초.

### Box

Box일 때만 연출을 더 강하게 한다.

`상자 닫기 → 리본 → 수하물 태그 → 컨베이어 → 비행기`

수하물 태그 예:

```text
WAY TO YOU

ICN → FLR

FOR SOFIA ♡

GIFT 0027
```

---

# 9. Globe / Airspace

홈의 대표 비주얼.

지구 위에:
- 두 사람의 도시 중심 프로필 마커
- 둘의 Route
- 현재 이동 중인 Gift
- 다른 사용자들의 익명 비행기

가 보인다.

사람 프로필은 공항이 아니라 도시 중심에 둔다. 기본 배송 공항은 프로필 위치와 분리해 저장하고 소포 Route의 출발·도착 기본값으로만 사용한다. 실시간 위치나 상대의 현재 위치를 표시하지 않는다.

프로필 마커는 원형 사진, 선택적인 Signal 이모지, 작은 배터리 상태로 구성한다. 탭하면 짧은 spring/halo와 selection 햅틱으로만 반응하고, 큰 callout이나 강제 카메라 이동은 하지 않는다. 이름·사진·Signal·배터리가 바뀌어도 사용자가 보고 있던 지구 시점은 유지한다.

배터리는 실시간 접속 상태가 아니라 연결된 두 사람만 공유하는 참고 정보다. 앱이 활성화된 동안만 수집하고 현재 연결 상대 외에는 읽을 수 없게 한다. 공개 API의 수치는 상태바보다 거칠 수 있으므로 마커에는 퍼센트를 쓰지 않고 작은 배터리 아이콘의 채움과 충전 상태만 표시한다. 알 수 없는 값은 표시하지 않으며, 10분이 지난 값은 흐리게 하고 60분이 지나면 아이콘을 숨긴다. 기기 이름·모델·식별자와 백그라운드 위치는 함께 저장하지 않는다.

### 내 비행기

항상 강조.

예:

`✈︎🎁`

탭하면:
- My Gift
- ICN → FLR
- Delivery progress

정도만 본다.

### 다른 사용자들의 비행기

목적은 소셜 기능이 아니라 **“세상 어딘가에서도 누군가가 마음을 보내고 있다”**는 느낌.

보여주는 정보:
- 출발지
- 도착지

보여주지 않는 정보:
- 사용자 이름
- 프로필
- 관계 정보
- Gift 내용
- 메시지
- 팔로우
- 좋아요
- 댓글

탭하면:

> Seoul → Paris  
> Someone is sending something.

정도만.

### Shared World


핵심 구조:

> **Private relationship + Shared world**

둘의 관계는 완전히 private.  
세상은 ambient하게 살아 있다.

---

# 10. Waiting Philosophy

기다림 자체가 목적이면 안 된다.

억지로 몇 시간을 못 열게 하면 피곤하다.

Way to You의 기다림은:
- 실제 거리를 상징하고
- 기대감을 만들고
- Gift를 메시지보다 특별하게 느끼게 하는 장치

여야 한다.

핵심:

> **Delayed Messaging이 아니라 Meaningful Delivery.**

---

# 11. Keepsakes

받은 것들은 채팅 로그가 아니라 **물건 컬렉션**으로 남는다.

예:
- Polaroids
- Voice Tapes
- Letters
- Tickets
- Boxes
- Route Tags

```text
VOICE TAPES

[ JUL 18 ]
[ JUL 29 ]
[ AUG 10 ]
```

각 물건에는 당시 Route가 남는다.

예:

`ICN → FLR`  
`JFK → ICN`  
`FLR → ICN`

시간이 지나면 둘 사이의 비행 기록과 기억이 함께 쌓인다.

---

# 12. Information Architecture

하단 탭은 최대 3개.

## Home

- Globe
- 상대 Signal
- 현재 배송 중 Gift
- Send something

## Keepsakes

- Polaroids
- Voice Tapes
- Letters
- Tickets
- Boxes

## Us

- 둘의 도시
- 관계 설정
- 초대 관리

---

# 13. Visual Direction

핵심 디자인 컨셉:

> **Retro communication, reimagined for long-distance love.**

소재:
- 삐삐
- 무전기
- 카세트
- 폴라로이드
- 손편지
- Air Mail
- 수하물 태그
- 항공권
- 공항 코드
- 소포
- 비행기

### 스타일 원칙

- 기본 구조는 매우 단순한 iOS
- 따뜻한 ivory / cream 계열
- 둥근 카드
- 얇은 선
- 작은 레트로 디테일
- 일부 모노스페이스 타이포
- SF Symbols 적극 활용
- 핵심 오브젝트만 커스텀 일러스트
- 짧은 햅틱
- 작은 기계음
- 애니메이션은 중요한 순간에만

### 핵심 원칙

> **80%는 단순한 iOS 앱, 20%의 순간에만 아주 귀엽게.**

---

# 14. Do Not Build

초기에는 다음을 만들지 않는다.

- 일반 채팅
- DM
- 공개 프로필
- 팔로우
- 댓글
- 좋아요
- 실시간 위치 추적
- 마지막 접속
- 읽음 표시
- 애정 점수
- 스트릭
- 과도한 푸시 알림
- 모든 행동에 긴 애니메이션

Way to You는 Social Network가 아니라:

> **Private relationship inside a shared world.**

---

# 15. MVP

## MVP 1

1. 회원가입
2. 커플 연결
3. 도시 설정
4. 도시 프로필 Globe
5. Heart
6. Signal
7. Interactive Widget
8. Polaroid
9. Voice Tape
10. Letter
11. 기본 배송 공항 설정과 Gift 작성 중 필요 시 변경
12. 기본 Gift Delivery와 배송별 Route
13. 익명 비행기
14. Keepsakes

## Later

- Touch
- Promise Ticket
- Box
- A/B Side Voice Tape
- Live Activity
- 수하물 벨트 연출
- 특별 배송 이벤트
- Route history
- 공항별 특별 디자인

---

# 16. Brand

## Name

**Way to You**

사용자에게 보이는 브랜드명은 항상 띄어쓴다.

## App Store 방향

예:

**Way to You: Long-Distance Love**

또는 추후 ASO 테스트.

## Brand Copy

> **Some things are worth waiting for.**

> **Feel close, even when you're apart.**

> **Little signals. Meaningful gifts.**

한국어:

> **빠르게 소비되는 메시지 대신, 기다리고 간직할 수 있는 마음을.**

> **떨어져 있어도, 서로를 가까이 느끼도록.**

---

# 17. Product Principle

Way to You의 경쟁 상대는 카카오톡이나 iMessage가 아니다.

그 앱들은 빠른 대화를 잘한다.

Way to You가 만들어야 하는 것은:
- 상대의 존재를 조용히 느끼는 것
- 답장을 요구하지 않는 신호
- 느리지만 의미 있는 전달
- 다시 꺼내볼 수 있는 기억
- 공항과 비행 사이에 쌓이는 둘만의 관계

최종적으로 Way to You는:

> **“멀리 있는 사람에게 마음이 가는 과정 자체를 경험하게 하는 앱.”**

이다.
