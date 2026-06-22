# 지적도 / 필지 시스템

구현: [scripts/parcel_loader.gd](../scripts/parcel_loader.gd), [scripts/parcel.gd](../scripts/parcel.gd)

## 데이터 소스
- `data/parcels.json` — **메인**. 표준 GeoJSON `FeatureCollection`, 필지 **4,409개**.
  - 좌표계: 한국 투영좌표(미터, EPSG:5186 추정). **1 유닛 = 1 미터**로 그대로 사용.
  - 전체 범위: X 약 4.46km × Y 약 6.48km.
- `data/parcels_wgs84.json` — 동일 데이터의 위경도(WGS84) 경량본. 참고/대안.

## GeoJSON 스키마
```jsonc
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Polygon", "coordinates": [[[x, y], ...]] },
      "properties": {
        "JIBUN": "435-3 과",          // 지번
        "PNU": "4157035026104350003", // 필지 고유번호
        "SGG_OID": 1396845,
        "BCHK": "1",
        "COL_ADM_SE": "41570"
      }
    }
  ]
}
```

## 로딩 방식 (`parcel_loader.gd`)
1. `FileAccess` + `JSON.parse_string`로 읽기.
2. 시작 기준점 `HOME=(161025, 573075)` — **필지가 가장 밀집한 지점**(분석 산출).
3. 기준점 반경 `LOAD_RADIUS=100m` 내 필지만 선별 (4,409개 전부 X — 러프 성능).
4. 좌표를 기준점 기준 로컬로 변환: `x→X`, `northing y→ -Z`.
5. `Geometry2D.triangulate_polygon`으로 삼각분할 → `ArrayMesh`(y=0 평면).
6. 필지 = `Parcel`(StaticBody3D) + MeshInstance3D + trimesh 충돌체(걸어다닐 바닥).

## 확장 포인트
- `HOME_X/Y`, `LOAD_RADIUS`만 바꾸면 다른 구역/전체 로드 가능.
- `Parcel.owner_id` 필드는 **점령전에서 소유권 단위로 재사용**.
- 폴리곤 구멍(내부 링)·비단순 폴리곤은 현재 무시/스킵 — 추후 보강.
