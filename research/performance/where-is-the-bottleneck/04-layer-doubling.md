# 04. Layer Doubling

Layer doubling is the largest single measured LABOS sub-block:

```text
layer doubling                6.036863 s   52.567% of LABOS CPU
doubled layers                1,075,939
doubling steps                8,389,666
steps per doubled layer             7.798
```

Each doubling step updates a layer reflection/transmission pair. In matrix notation:

```text
Q      = qseries(R * R)
D      = T + Q * diag(E) + Q * T
rd     = R * D
U      = R * diag(E) + rd
tu     = T * U
R_next = R + diag(E) * U + tu
td     = T * D
T_next = diag(E) * D + T * diag(E) + td
```

The trace counted:

```text
q-series nonzero calls        3,408,299
q-series skipped checks       4,981,367
R*D products                  8,389,666
T*U products                  8,389,666
T*D products                  8,389,666
semulAdd updates              8,389,666
matAddEsmul3 updates          8,389,666
esmulSemulAdd updates         8,389,666
```

This is why doubling is the final frontier. The code has already specialized the common matrix shape and fused several updates, but the exact calculation still has to run the same scientific recurrence millions of times.

A small assembly improvement can reduce a primitive. It does not remove:

```text
3,874 wavelengths
* active Fourier terms
* active layers
* repeated doubling steps
```

The next large speedup would need to reduce one of those counts or introduce a new scientifically valid reuse boundary.
