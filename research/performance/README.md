# Performance Research

This folder tracks durable performance findings for zdisamar. The current scope is per-spectrum O2 A forward-model runtime only. Retrieval-loop reuse and `prepare_o2a` are separate topics.

## Documents

- [O2 A per-spectrum wall](o2a-per-spectrum-wall.md): measured wall, code path, and timing decomposition.
- [LABOS core primitives](labos-core-primitives.md): the math kernels and low-level CPU pressure behind the wall.
- [O2 A core primitive demo](o2a-core-primitive-demo.ipynb): Jupyter notebook that runs the Zig LABOS kernel benchmark and reconstructs the doubling primitive cost.

## Run the notebook

From the repo root:

```sh
uvx --from jupyterlab jupyter lab research/performance/o2a-core-primitive-demo.ipynb
```

`uvx` runs JupyterLab in a temporary tool environment, so contributors do not need to install Jupyter into the repo environment first.

## Current finding

The per-spectrum wall is exact high-resolution support fan-out. A 701-sample O2 A spectrum expands to 3,874 unique radiance wavelengths. Runtime is spent precomputing exact-wavelength forward solves. Within each solve, LABOS transport dominates, especially Fourier RT-layer construction and layer doubling.

The concise model is:

```text
T_spectrum ~= T_wavelength_sampling
           + max_worker sum(lambda in unique_radiance_support)
               [T_configured_input(lambda) + T_LABOS(lambda)]
           + O(n_nominal)
```

The product of exact support wavelengths, Fourier terms, RT layers, and doubling steps is the wall.
