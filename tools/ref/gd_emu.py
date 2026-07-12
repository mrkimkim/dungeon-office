"""
GDScript의 부호 있는 64비트 정수 의미론을 Python에서 에뮬레이션해,
GDScript로 옮길 PCG32 구현이 레퍼런스(sim.Pcg32)와 동일한 u32 스트림을
내는지 이 환경에서 검증한다. 통과하면 아래 gd_* 로직을 GDScript로 1:1 전사한다.

GDScript 사실:
 - int는 부호 있는 64비트. 곱셈·덧셈은 2^64로 랩(2의 보수).
 - `>>`는 산술 시프트(부호 확장). 논리 우시프트는 없다 → _lsr64 헬퍼로 흉내.
 - `<<`, `&`, `^`, `|`는 비트 그대로.
"""

import sim as S

MASK64 = (1 << 64) - 1


def w64(x):
    """부호 있는 64비트로 랩."""
    x &= MASK64
    if x >= (1 << 63):
        x -= (1 << 64)
    return x


def lsr64(v, n):
    """논리 우시프트(부호 없는 >>>)를 GDScript 연산만으로: 산술 >> 후 상위 n비트를 마스크.
    GDScript 전사: return (v >> n) & ((1 << (64 - n)) - 1)  # n in 1..63"""
    if n == 0:
        return v
    return (v >> n) & w64((1 << (64 - n)) - 1)  # w64로 마스크가 GDScript 리터럴과 동일해짐


def gd_next_u32(st):
    """st = [state, inc] (둘 다 부호 있는 64비트). 레퍼런스 next_u32의 GDScript판."""
    old = st[0]
    st[0] = w64(old * 6364136223846793005 + st[1])
    xorshifted = w64((lsr64(old, 18) ^ old))
    xorshifted = lsr64(xorshifted, 27) & 0xFFFFFFFF
    rot = lsr64(old, 59) & 63  # rot in 0..31 (상위 5비트)
    res = ((lsr64(xorshifted, rot)) | w64(xorshifted << (((-rot) & 31)))) & 0xFFFFFFFF
    return res


def gd_seed(init_state, init_seq):
    st = [0, w64((init_seq << 1) | 1)]
    gd_next_u32(st)
    st[0] = w64(st[0] + w64(init_state))
    gd_next_u32(st)
    return st


def main():
    # 여러 시드에서 레퍼런스와 GD-에뮬의 u32 스트림 100개씩 비교
    seeds = [(0, 0xDA), (12345, 1), (S.round_seed("r1", 0), 0xDA), (S.round_seed("r2", 3), 0xDA)]
    total = 0
    for init_state, init_seq in seeds:
        ref = S.Pcg32.seeded(init_state, init_seq)
        gd = gd_seed(init_state, init_seq)
        for i in range(100):
            a = ref.next_u32()
            b = gd_next_u32(gd)
            total += 1
            if a != b:
                print(f"MISMATCH seed=({init_state},{init_seq}) draw#{i}: ref={a} gd={b}")
                raise SystemExit(1)
    print(f"OK — GD-에뮬 PCG32가 레퍼런스와 {total} draw 전부 일치. GDScript 전사 안전.")


if __name__ == "__main__":
    main()
