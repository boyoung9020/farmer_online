# 농사 시스템 (트랙터 · 대규모)

구현: [scripts/farm_field.gd](../scripts/farm_field.gd), [scripts/player_controller.gd](../scripts/player_controller.gd), [scripts/game_manager.gd](../scripts/game_manager.gd)

사람이 한 칸씩 하지 않고, **트랙터가 작업 폭(8m)만큼 지나가며 일괄 처리**한다.
농지는 셀 격자(30×20 = 600셀, 60×40m). 각 셀이 아래 상태머신을 가진다.

## 셀 상태머신
```
EMPTY ──일구기──▶ TILLED ──심기(-씨앗값)──▶ PLANTED
                    ▲                           │ (시간)
                    │                           ▼
               수확(+수익) ◀── MATURE ◀──(시간)── GROWING
```

## 트랙터 작업 모드
- **1** 운전(작업 없음) · **2** 일구기 · **3** 심기 · **4** 수확
- 모드를 켜고 트랙터가 셀 위를 지나가면 해당 동작을 자동 적용(셀당 1회, 멱등).
- 작업 폭 `WORK_WIDTH=8m` (앞쪽에서 5개 지점 샘플 → 폭 전체 커버).

## 수치 (러프 기본값)
| 항목 | 값 | 위치 |
|------|-----|------|
| 농지 | 30×20셀, 셀 2m (60×40m) | `farm_field.gd` |
| 씨앗값 `SEED_COST` | 2원/셀 | `farm_field.gd` |
| 수확 수익 `HARVEST_VALUE` | 10원/셀 | `farm_field.gd` |
| 단계별 성장 `GROW_TIME` | 4초 (×2단계=8초) | `farm_field.gd` |
| 초기 자금 | 300원 | `game_manager.gd` |
| 트랙터 최고속/가속/조향 | 12 / 14 / 1.8 | `player_controller.gd` |

→ 셀당 순익 8원. 600셀 다 키우면 약 4,800원.

## 시각 피드백 (현재: 기본 도형)
- 미경작=풀색, 흙=갈색, 작물=초록 박스(성장에 따라 높이↑), MATURE=노란색.

## 추후 개선 (TODO)
- 작물 종류 분화, 물주기·날씨, 판매대, 트랙터 작업기 교체 연출.
- 성장 갱신을 "자라는 셀 목록"만 순회하도록 최적화.
- Kenney 트랙터/작물 모델로 교체.
