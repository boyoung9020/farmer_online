# 노동자 / 캐릭터 시스템

구현: [scripts/worker.gd](../scripts/worker.gd), [scripts/worker_manager.gd](../scripts/worker_manager.gd), [scripts/farmer.gd](../scripts/farmer.gd), [scripts/tractor.gd](../scripts/tractor.gd), [scripts/human_mesh.gd](../scripts/human_mesh.gd)

## 캐릭터
- **기본은 사람(농부, 도보)**. 외형은 블록형 휴머노이드(머리·몸통·팔·다리·밀짚모자) — `human_mesh.gd`가 코드로 조립. (추후 무료 CC0 glTF 모델로 교체)
- **트랙터는 탈것**. 농부가 트랙터 근처에서 **F**로 탑승/하차. 탑승 시 차량 운전 + 작업 모드.

## 고용 (상점 UI)
- 단축키가 아니라 **고용소(상점) 모델**에서 고용한다. 농부가 상점 5m 이내에서 **E** → 패널이 열림([shop.gd](../scripts/shop.gd), [shop_ui.gd](../scripts/shop_ui.gd)).
- 패널 버튼:
  - **농사 노동자 (120원)** — 밭을 돌며 **자동으로 일구기→심기→수확**.
    - `farm_field.request_job()`이 가장 가까운 "할 일 있는 셀"과 모드를 반환(심기는 돈 있을 때만).
  - **군사 (150원)** — **집결지(RALLY)** 에 모여 적에 대비/교전.
- UI 열려 있는 동안 농부 이동 정지, 마우스 표시. ESC/닫기로 닫음.
- HUD에 `아군 농사 N / 군사 M`, `적군 K` 표시(그룹 크기로 집계).

## 외형 색 구분
| 대상 | 셔츠 | 모자 |
|------|------|------|
| 농부(플레이어) | 파랑 | 밀짚 |
| 농사 노동자 | 초록 | 밀짚 |
| 군사 | 붉은 군복 | 헬멧(회색) |

## 추후 (TODO)
- 노동자 길찾기(NavigationServer3D), 작업 애니메이션.
- 군사: 무기/스탯, 점령전 전투 연동.
- 고용 UI 패널(현재는 H/J 단축키), 노동자 임금/유지비.
