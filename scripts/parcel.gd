extends StaticBody3D
class_name Parcel
## 지적도 필지 한 개. 걸어다닐 수 있는 바닥이자, 추후 점령전의 점령 단위.

var jibun: String = ""    # 지번 (예: "435-3 과")
var pnu: String = ""      # 필지 고유번호 (PNU)
var owner_id: int = 0     # 0=중립, 1=플레이어 ... (점령전용, 추후 사용)
