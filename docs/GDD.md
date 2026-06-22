# 보구곶리 온라인 — 게임 디자인 개요 (GDD)

> 기획 관리(dcos)는 이 `docs/` 폴더의 마크다운으로 한다.

## 한 줄 컨셉
실제 **보구곶리 지적도**를 무대로, 농부가 밭을 일궈 돈을 벌고 → 용병을 고용해 이웃 필지를 점령해 나가는 3D 게임.

## 코어 루프
1. **농사** — 이동 → 일구기 → 모종 심기 → 성장(시간) → 수확 → 돈.
2. **점령전(추후)** — 번 돈으로 용병 고용 → 적 필지 공격 → 소유권 획득.

## 현재 구현 범위 (러프 1단계)
- ✅ 농사 루프 (밭 격자 4×4, 상태머신, 성장 타이머, 수익)
- ✅ 지적도 GeoJSON → 3D 필지 바닥 생성 (시작 기준점 반경 100m)
- ✅ 3인칭 농부 이동/시점, HUD(돈/메시지/조작)
- ⬜ 무료 CC0 에셋(Kenney) 적용 — 기본 도형 검증 후
- ⬜ 점령전 — `03-combat-conquest.md` 참고

## 기술 스택
- 엔진: **Godot 4.6.3 stable**
- 언어: GDScript
- 데이터: 보구곶리/성동/용강리 지적도 GeoJSON (필지 4,409개)

## 문서 목록
- [01-farming-system.md](01-farming-system.md) — 농사 루프 상세
- [02-land-parcel-system.md](02-land-parcel-system.md) — 지적도/필지 시스템
- [03-combat-conquest.md](03-combat-conquest.md) — 점령전 (로드맵)
- [roadmap.md](roadmap.md) — 단계별 일정
