# 카메라 하강 애니메이션 — 재사용 노트

작성일: 2026-08-13
구현: `WayToYou/Features/Home/GlobeMapView.swift` — `GlobeMapView.CameraDive`, `Coordinator.beginCameraDive` / `advanceCameraDive` / `finishCameraDive` / `cancelCameraDive`
커밋: `fd8c114 Dive into the globe instead of snapping to the region`

전 지구 카메라에서 지역 카메라로 "쭈우욱 내려가는" 이동을 만드는 방법을 남긴다.
지구본 말고 다른 화면에서도 같은 기법을 쓸 수 있게 원리와 함정을 함께 적는다.

## 왜 `setCamera(animated: true)`로는 안 되는가

MapKit의 기본 카메라 애니메이션은 `centerCoordinateDistance`를 **선형으로** 줄인다.
그런데 화면에서 느껴지는 확대 속도는 거리 자체가 아니라 **거리의 로그 변화율**이다.
카메라가 화면에 담는 폭은 거리에 비례하므로, 거리가 절반이 될 때마다 배율이 2배가 된다.

16.8M m에서 5M m까지 선형으로 줄이면 시간의 절반이 지났을 때 거리는 10.9M m이지만
배율로는 전체의 32%밖에 진행하지 않았다. 앞부분은 거의 멈춘 것처럼 보이다가
마지막에 한 번에 꽂히는 움직임이 되고, 이게 원래 문제였던 "0.2초 만에 끝나는" 느낌의 정체다.

`UIView.animate(withDuration:)`로 감싸면 지속 시간은 늘어나지만 곡선은 그대로라
"느리게 멈춰 있다가 느리게 꽂히는" 더 나쁜 결과가 된다. 지속 시간이 아니라 곡선을 바꿔야 한다.

## 해법 1 — 거리는 로그(기하) 보간

```
d(t) = d0 × (d1 / d0)^p        p = 0…1 진행률
```

이러면 매 순간 배율이 같은 비율로 커져서, 시작부터 끝까지 같은 속도로 파고드는 느낌이 된다.
검증할 때는 거리 자체가 아니라 **초당 옥타브 수** `|log2(d_n / d_{n-1})| / Δt`를 찍어 본다.
이 값이 구간 내내 평평해야 맞는 곡선이다.

## 해법 2 — 속도 곡선은 비대칭 사다리꼴

ease-in-out(3차·5차 모두)은 속도가 한가운데서 한 번 부풀었다 꺼지는 종 모양이라
한 번 "펌프"하고 끝난다. "쭈우욱"은 지속되는 소리라서 등속 구간이 있어야 한다.
가장 흔한 곡선이라 티도 많이 난다.

속도 프로파일을 `가속 → 등속 → 감속` 사다리꼴로 두고 그걸 적분해서 진행률로 쓴다.
가속·감속 램프는 smoothstep `s(x) = x²(3−2x)`를 쓰고, 0…1 적분값이 정확히 `1/2`이라
구간 면적이 곧 `길이 / 2`가 되어 정규화가 간단하다.

현재 값은 `rampIn = 0.10`, `rampOut = 0.45`다. 감속을 가속의 4배 이상으로 길게 잡아야
도착이 "쿵" 멈추지 않고 미끄러지듯 잦아든다. 출발을 더 부드럽게 하려면 `rampIn`을 키우되,
전체 시간이 길어질수록 절대 시간도 같이 늘어나 굼떠 보이는 점을 감안한다.

스프링·오버슈트는 쓰지 않는다. 검증하지 않은 더 가까운 거리까지 순간적으로 들어갔다 나오는데,
지도에서는 그게 버그처럼 읽힌다.

## 해법 3 — 시간은 배율의 로그에 비례

```
T = clamp(0.95 + 0.62 × ln(zoomScale), 1.0, 2.4)   // 초
```

배율이 크면 지나야 할 옥타브 수도 많다. 시간을 고정하면 도시 조합에 따라 체감 속도가 달라진다.
로그에 맞춰 늘리면 어떤 조합에서도 초당 옥타브 수가 비슷하게 유지된다.
기기마다 화면 폭이 달라 `zoomScale` 자체가 다르게 계산되는데, 이 공식이 그것도 함께 흡수한다.

## 해법 4 — 중심 이동은 대권 slerp, 그리고 앞당기기

위경도를 선형 보간하면 극지방과 날짜변경선에서 경로가 휜다.
`SphereVector.moved(toward:by:)`가 이미 3D 단위벡터 slerp라 그대로 쓰면 된다.

여기에 더해 회전을 **높은 고도에서 미리 끝내야** 한다. 같은 각도라도 낮게 내려올수록
화면에서 훨씬 많이 움직이기 때문에, 진행률을 그대로 쓰면 마지막 20%의 회전이
처음보다 몇 배 많은 픽셀을 먹고 착지 직후 옆으로 미끄러지는 것처럼 보인다.

화면상 이동 속도를 균일하게 만드는 보정은 거리에 비례해 각도를 진행시키는 것이고,
`d(t) = d0·r^p`를 적분하면 다음이 나온다.

```
φ(p) = (1 − r^p) / (1 − r)        r = d1 / d0 = 1 / zoomScale
```

## 함정 — `MKMapView.camera`는 복사본이 아니다

이번에 하루를 날린 지점이다. `mapView.camera`는 **살아 있는 카메라 객체**를 돌려준다.

```swift
let camera = mapView.camera                     // 지도의 카메라 그 자체
camera.centerCoordinateDistance /= zoomScale    // ← 지도 카메라를 직접 고친 것
let start = mapView.camera                      // ← 방금 고친 그 객체가 또 나옴
```

출발과 목적지가 같은 값이 되어 보간 구간이 0으로 무너지고, 하강이 첫 프레임에 끝난다.
증상이 헷갈리는 이유는 **다른 트랙은 정상으로 보인다**는 점이다. 다리 접기는 `zoomScale`을
직접 받아 자기 시간표대로 도니까, 카메라만 즉시 끝나고 다리는 몇 초간 혼자 접힌다.

규칙: **목적지를 만들기 전에 출발 값을 스칼라로 먼저 복사하고, 커밋하는 카메라는 매번 새로 만든다.**

```swift
let startCenter = mapView.camera.centerCoordinate
let startDistance = mapView.camera.centerCoordinateDistance
let startHeading = mapView.camera.heading

let target = MKMapCamera(
    lookingAtCenter: destination,
    fromDistance: startDistance / zoomScale,
    pitch: 0,
    heading: startHeading
)
```

안전장치로 `startDistance > targetDistance`를 guard에 넣어 뒀다. 다시 두 값이 같아지면
애니메이션 없이 즉시 이동하고 부수 효과도 함께 정리되므로, 트랙이 어긋난 채로 도는 상태가 안 나온다.

## 함정 — delegate가 매 프레임 터진다

매 프레임 `setCamera(animated: false)`를 부르면 그때마다
`regionWillChange → didChangeVisibleRegion → regionDidChange`가 통째로 불린다.
`isDivingCamera` 플래그로 세 개를 모두 막고, 하강 시작에 `beginUserCameraMotion()`을 한 번,
착지에 `scheduleBacksideReveal(afterDisplayFrames: 3)`을 한 번만 부른다.

착지 프레임에서는 **`setCamera`를 먼저 부르고 그 뒤에 마무리**해야 한다.
순서가 반대면 `isDivingCamera`가 이미 꺼진 상태로 마지막 `setCamera`가 delegate를 타고,
`beginUserCameraMotion()`이 방금 건 `scheduleBacksideReveal`을 지워 버린다.

## 함정 — 마커 분류를 얼려야 한다

하강 중에는 `updateMarkerRepresentations`를 막는다(`isDivingCamera`를 guard에 추가).
지구본은 최대 257개의 투영 probe annotation의 화면 좌표를 읽어 지평선 클리핑을 계산하는데,
이것들이 매 프레임 화면을 드나들기 때문에 한 프레임만 잘못 읽어도
멀쩡히 보이는 도시가 `.backside`로 판정되어 아바타가 비행 도중 사라진다.

프로필은 실제 `MKAnnotation`이라 MapKit이 알아서 매 프레임 재투영한다. 직접 옮길 필요가 없다.

## 부수 효과 — 순간 전환은 느린 애니메이션에서 드러난다

원래 마커의 다리(선 + 점)는 확대 시작 순간 사라지면서 아바타 앵커가 42pt 튀었다.
빠른 애니메이션에 가려져 있었을 뿐이라, 느리게 만들자마자 그대로 보였다.

`setShowsCoordinateLeg(Bool)`을 `setCoordinateLegProgress(Double)`로 바꿔서
`centerOffset.y`를 `pinCenterOffset(−41)`과 `avatarCenterOffset(+1)` 사이에서 보간한다.
점의 캔버스 좌표를 `canvasHeight / 2 − centerOffset.y`로 계산하면
**보간 중에도 점이 항상 도시 좌표 위에 남고**, 줄기만 짧아지며 아바타가 그 위로 내려앉는다.

교훈으로 남길 것: 애니메이션을 느리게 만들면 그 애니메이션과 함께 일어나던
**모든 순간 전환이 같이 드러난다**. 지속 시간을 늘릴 때는 동시에 바뀌는 다른 상태도 같이 훑어본다.

## 중단 처리

- 사용자 제스처: `regionWillChangeAnimated`에서 `hasActiveMapGesture`가 참이면 즉시 카메라를 넘긴다.
  매 tick에서도 한 번 더 확인한다(제스처가 region 변경 없이 시작될 수 있다).
- 경로 변경: `requestInitialFraming`에서 `cancelCameraDive(settlingLeg: false)` 후 다리를 1로 되돌린다.
- 뷰 해제: `disconnect()`에서 display link를 무효화한다(`CADisplayLink`는 target을 강하게 잡는다).
- Reduce Motion: 하강을 건너뛰고 같은 목적지 카메라를 즉시 적용한다.

## 확인되지 않은 것

`MKImageryMapConfiguration`(위성·지구본)에서 매 프레임 카메라를 직접 커밋하면
MapKit이 경로를 미리 모르기 때문에 타일을 선반입하지 못한다.
내려가는 동안 해상도가 계단식으로 튈 수 있고, 이건 소스만 봐서는 알 수 없다.
그렇게 보이면 조절 손잡이는 **지속 시간**이다(각 해상도 단계에 머무는 시간이 늘어난다).
