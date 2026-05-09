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
direct forward-only median       0.841938 s
direct forward+jacobian median   1.010729 s
non-session retrieval elapsed time       5.354143 s
session reused retrieval elapsed time    4.098390 s
iterations                       4
same retrieved state             true
```

Use this case for focused latency work before scaling up broad paired sweeps.
