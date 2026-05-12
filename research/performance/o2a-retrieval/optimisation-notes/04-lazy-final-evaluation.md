# 04. Defer Final-State Evaluation

Historical checkpoint: `719eb0b -> e044099`, where the slow retained retrieval
loop moved from `5.266814 s` to `4.134691 s`.

In short: return the converged state as soon as the retrieval loop is done, and
calculate the exact final-state spectrum only when a caller asks for it.

Source links:

- DISAMAR
  - No direct Fortran analogue is used here. This is a zdisamar Python result
    lifecycle optimization around the in-process forward model.
- zdisamar
  - [Result final-evaluation property](https://github.com/bout3fiddy/zdisamar/blob/e044099dc56f5df3841b74f209dfb4bb06a695822/python/zdisamar/inverse_method/optimal_estimation/retrieval.py#L26-L57): exposes the final evaluation lazily and caches the result.
  - [Final-evaluation attachment](https://github.com/bout3fiddy/zdisamar/blob/e044099dc56f5df3841b74f209dfb4bb06a695822/python/zdisamar/inverse_method/optimal_estimation/o2a.py#L140-L177): installs the final-state evaluation factory when the retrieval result does not already contain that product.
  - [Slow benchmark accounting](https://github.com/bout3fiddy/zdisamar/blob/e044099dc56f5df3841b74f209dfb4bb06a695822/validation/optimal_estimation/benchmark_slow_forward_jacobian.py#L330-L369): records retrieval-only time, lazy-final time, and retrieval plus lazy-final time separately.

The final-state spectrum is needed for plotting residuals and Jacobians at the
converged state. It is not needed to return the converged state vector and
iteration diagnostics.

```python
# Eager route: retrieval pays for final products before returning.
result = solve_state_vector()
result.final_evaluation = evaluate_forward_and_jacobian(result.state)
return result

# Lazy route: retrieval returns immediately; plot consumers pay later.
result = solve_state_vector()
result.attach_final_evaluation(
    lambda: evaluate_forward_and_jacobian(result.state)
)
return result
```

The current retained slow-case artifact reports:

```text
retrieval loop wall time            2.835175 s
forward+jacobian time               2.834102 s
lazy final evaluation on demand      1.297817 s
lazy final evaluation cached        true
```

This optimization does not remove the exact final-state calculation. It moves
that calculation out of the retrieval critical path for callers that only need
the retrieved state and diagnostics.
