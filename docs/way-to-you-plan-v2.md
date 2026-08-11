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

- 짧은 존재 표현 → `Ping`
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

### Step 2 — Your Airport

도시 주변 공항 리스트를 보여준다.

예:

**Seoul**
- ICN · Incheon International
- GMP · Gimpo International

질문:

> **Which airport brings your partner to you?**

또는:

> **연인이 당신을 만나러 올 때, 어느 공항으로 오나요?**

사용자가 하나를 선택한다.

### Step 3 — Partner Connection

상대를 초대한다.

상대방도:
- 도시
- 공항

을 선택한다.

### Step 4 — Your Route

둘이 연결되면 앱이 둘의 관계를 하나의 Route로 보여준다.

예:

`ICN ↔ FLR`

카피:

> **Your Route**

이 Route가:
- Globe
- Gift Delivery
- Air Mail
- Keepsakes
- 수하물 태그

전부의 기준이 된다.

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
- 사용자가 선택한 공항
- 둘의 고정 Route

즉:

> **사람을 추적하지 않고, 관계의 두 기준점을 연결한다.**

---

# 6. Core Interaction Model

Way to You의 표현 강도는 세 단계로 나뉜다.

`Ping → Signal → Gift`

## 6.1 Ping

가장 가벼운 표현.

목적:

> “그냥 네 생각났어.”

UI:

`♡ PING`

한 번 누르면 상대에게 짧은 햅틱과 신호만 간다.

특징:
- 텍스트 없음
- 읽음 표시 없음
- 답장 의무 없음
- 대화창 없음
- 상대도 Ping으로 되돌려줄 수 있음

## 6.2 Signal

Signal은 삐삐 / 무전기 감성으로 만든다.

목적:

> “나 지금 이런 상태야.”

예:
- 🌙 Sleeping
- 💻 Focusing
- ☕ Free
- 🚶 Out
- 🏠 Resting

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

작은 지구 위에:
- 두 사람의 공항
- 둘의 Route
- 현재 이동 중인 Gift
- 다른 사용자들의 익명 비행기

가 보인다.

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
- 공항
- Your Route
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
4. 공항 선택
5. `Your Route`
6. Ping
7. Signal
8. Interactive Widget
9. Polaroid
10. Voice Tape
11. Letter
12. 기본 Gift Delivery
13. Globe
14. 익명 비행기
15. Keepsakes

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
