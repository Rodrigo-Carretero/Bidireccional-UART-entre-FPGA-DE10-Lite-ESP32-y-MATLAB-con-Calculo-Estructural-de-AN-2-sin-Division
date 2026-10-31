"""Modelo independiente: verifica rango y aritmetica EXACTA de la FPGA.
Se ejecuta con Python 3: python verificar_matematica.py
"""
from math import isqrt
UINT32_MAX = (1 << 32) - 1
UINT64_MAX = (1 << 64) - 1


def fpga_model(A: int, n_dec: str):
    if not n_dec or any(c not in '0123456789' for c in n_dec):
        return 2, 0
    n_sat = 0
    for digit in n_dec:
        n_sat = min(64, 10 * n_sat + ord(digit) - 48)
    if A == 0:
        return 0, int(n_sat == 0)
    if A == 1 or n_sat == 0:
        return 0, 1
    if n_sat >= 64:
        return 1, 0
    power = 1
    for _ in range(n_sat):
        power *= A
        if power > UINT64_MAX:
            return 1, 0
    return 0, isqrt(power)


def reference(A: int, n: int):
    # Python maneja enteros de tamano arbitrario; resultado exacto.
    r = isqrt(pow(A, n))
    if r > UINT32_MAX:
        return 1, 0
    return 0, r


def main():
    total = 0
    for A in range(256):
        for n in range(0, 72):
            assert fpga_model(A, str(n)) == reference(A, n), (A, n)
            total += 1
    for A, n in [(1, '9'*1000), (0,'9'*1000), (2,'9'*1000),
                  (255,'00000000007'),(2,'0000000063'), (255,'00000000009')]:
        sat = min(64, int(n))
        assert fpga_model(A,n) == reference(A,sat), (A,n)
        total += 1
    assert fpga_model(4, '7') == (0,128)
    assert fpga_model(4, '10') == (0,1024)
    assert fpga_model(2, '40') == (0,1048576)
    assert fpga_model(2, '63') == (0,3037000499)
    assert fpga_model(2, '64') == (1,0)
    assert fpga_model(255, '8') == (0,4228250625)
    assert fpga_model(255, '9') == (1,0)
    print(f'PASSED: {total} comprobaciones exactas.')

if __name__ == '__main__':
    main()
