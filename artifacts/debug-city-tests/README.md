# 지구본 DEBUG 도시 캡처

준대척·극점 인접 도시 조합의 첫 홈 화면 카메라를 비교한 PNG 50장을 `png/` 한 폴더에 보관한다.

파일명은 `단계--도시쌍.png` 형식이다. 같은 도시 조합의 중간 실험을 덮어쓰지 않도록 기존 하위 폴더 이름을 단계 접두어로 옮겼다.

- `baseline--*`: 변경 전 기준 8장
- `polar-midpoint--*`, `after-camera-fallback--*`, `after-camera-fallback-v2--*`: 중간 카메라 후보 13장
- `diagnostic-*`: 상수와 중심점을 비교한 진단 캡처 13장
- `final-camera--problem--*`: 문제 조합 최종 결과 8장
- `final-camera--regression--*`: 기존 정상 조합 최종 회귀 결과 5장
- `final-camera--medellin-palembang.png`, `final-camera--quito-kuala-lumpur.png`: 최종안 개별 확인 2장
- `final-camera--problem-cases-contact-sheet.png`: 문제 조합 최종 비교 시트 1장

새 캡처도 `scripts/capture-debug-home.sh`의 출력 경로를 이 폴더로 지정하고, 기존 단계와 구분되는 접두어를 붙인다.
