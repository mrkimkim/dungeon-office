# PCG32 — 던전 오피스 결정론 RNG (플랫폼 §3.3)
#
# 이 알고리즘은 Python 레퍼런스(tools/ref/sim.py:Pcg32)와 동일하며,
# tools/ref/gd_emu.py가 GDScript의 부호 있는 64비트 의미론을 에뮬레이션해
# 두 구현이 400 draw 전부 일치함을 이 환경에서 검증했다.
#
# 유일한 RNG 소비자는 의뢰 생성기다(원칙 4 — 승패 주사위 없음).
class_name Pcg32
extends RefCounted

var state: int = 0
var inc: int = 0

# 논리 우시프트(부호 없는 >>>)를 GDScript 연산만으로. `>>`는 산술 시프트라
# 상위 n비트를 마스크로 지운다. (n in 1..63)
static func _lsr64(v: int, n: int) -> int:
	if n == 0:
		return v
	return (v >> n) & ((1 << (64 - n)) - 1)

func seed_with(init_state: int, init_seq: int) -> void:
	state = 0
	inc = (init_seq << 1) | 1
	next_u32()
	state = state + init_state  # 64비트 랩(2의 보수)
	next_u32()

func next_u32() -> int:
	var old := state
	state = old * 6364136223846793005 + inc  # 오버플로 랩 = mod 2^64
	var xorshifted := _lsr64(old, 18) ^ old
	xorshifted = _lsr64(xorshifted, 27) & 0xFFFFFFFF
	var rot := _lsr64(old, 59) & 63
	var res := (_lsr64(xorshifted, rot) | (xorshifted << ((-rot) & 31))) & 0xFFFFFFFF
	return res

# [0, bound) 균등, 편향 제거(rejection). bound>0.
func below(bound: int) -> int:
	if bound <= 0:
		return 0
	var threshold := (4294967296 - bound) % bound  # (2^32 - bound) % bound
	while true:
		var r := next_u32()
		if r >= threshold:
			return r % bound
	return 0

# [lo, hi] 포함
func between(lo: int, hi: int) -> int:
	return lo + below(hi - lo + 1)
