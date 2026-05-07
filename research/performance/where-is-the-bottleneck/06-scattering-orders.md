# 06. Scattering Orders

Scattering orders are the second major LABOS block:

```text
orders total                  2.826031 s   24.608% of LABOS CPU
orders calls                    120,390
initial-return calls             66,429
multiple-order iterations       258,796
```

The split is:

```text
initial sources               0.130322 s
initial transport             0.324308 s
multiple loop                 2.198735 s
local down                    0.623497 s
local up                      0.609598 s
transport                     0.663621 s
accumulate                    0.277443 s
```

The hot primitive inside the multiple-scattering loop is the paired 10-term Gauss dot:

```text
dotGaussPair calls          295,581,240
multiply-add terms        2,955,812,400
inactive down-layer skips     5,499,208
inactive up-layer skips       5,499,208
```

The inactive-layer skip is already doing useful work. The remaining orders cost is the active multiple-scattering propagation that LABOS still has to perform until the order contribution falls below the convergence threshold.
