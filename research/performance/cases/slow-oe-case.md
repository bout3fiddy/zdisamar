# Slow OE Case

The slow retained zdisamar OE case comes from paired sweep case 71.

Scene:

```text
solar zenith              53.760296 deg
viewing zenith            45.712144 deg
relative azimuth           7.023280 deg
surface pressure         896.819425 hPa
surface albedo             0.195289
aerosol optical depth      1.968191
aerosol mid pressure     329.192075 hPa
```

Initial state:

```text
aerosol optical depth      1.742008
aerosol mid pressure     354.192075 hPa
```

Retained benchmark:

```text
validation/outputs/optimal_estimation/zdisamar_o2a_slow_forward_jacobian_benchmark.json
```

Current key numbers:

```text
direct forward-only median       0.744821 s
direct forward+jacobian median   0.901555 s
session reused retrieval elapsed time    2.835175 s
lazy final evaluation when requested     1.297817 s
iterations                       3
lazy final evaluation cached     true
```

Use this case for focused latency work before scaling up broad paired sweeps.
