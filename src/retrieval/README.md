# `retrieval/` — fitting the aerosol state to a measurement

The forward pass computes the spectrum a scene would produce. The retrieval runs
it backwards: given a measured reflectance spectrum, find the aerosol state that
reproduces it. It is Rodgers optimal estimation over a fixed two-element state,
the aerosol optical depth and the aerosol layer's mid-pressure in hPa. Each
iteration runs one forward pass at the current state, weighs the mismatch against
the measurement, and steps the state toward a better fit.

The loop that calls the forward model lives in `src/root.zig`
(`runOptimalEstimation`). This folder holds what that loop needs: the state
vocabulary, the linear algebra of one step, the convergence test, and the owners
that carry the result back to Python.

```
root.zig drives the loop:

measurement (reflectance, variance)  +  prior aerosol state
   |
   v
each iteration:
   |
   |   forward pass (root.zig)   ->  reflectance + Jacobian
   |   accumulateNormalSystem    ->  whitened normal system G, b
   |   solveStep                 ->  damped Rodgers step, new state
   |   clamp to bounds, record the iteration
   |   quadraticForm             ->  converged?
   |
   v
invertSymmetric, multiply  ->  posterior covariance + averaging_kernel
   |
   v
Result: retrieved state, its uncertainty, and the iteration history
```

## The state space (`retrieval/root.zig`)

The state is two lanes, fixed for the whole model and shared with the forward
Jacobian in `rtm/jacobian_states.zig`: lane 0 is the aerosol optical depth, lane 1
is the aerosol layer's mid-pressure. Each lane is a `StateScalar` carrying its
initial guess, its prior mean, its prior variance, and optional physical bounds.
The variances form the diagonal prior covariance `Sa`. The measurement variances
are the diagonal `Se`; their reciprocal is stored once as `inv_variance`, the
`1/variance` the normal system reads.

The radiative transfer returns the pressure lane's derivative in altitude, but the
state is a pressure, so that lane also carries a `PressureAltitudeProfile`, a
spline of `log(pressure)` against altitude built by `buildPressureProfile`.
`altitudeDerivativeAtPressure` inverts that curve to get the altitude-versus-
pressure slope (`d altitude / d pressure`, in km per hPa) at the current pressure,
and scales the pressure-lane Jacobian by it, turning a per-altitude derivative
into a per-pressure one.

## One iteration (`retrieval/root.zig`)

`accumulateNormalSystem` builds the normal system from one forward pass. It works
in prior-whitened coordinates, where the prior covariance is the identity, so the
update stays stable even though the two lanes have very different magnitudes (an
optical depth near one, a pressure in the hundreds). Streaming every product
wavelength, with residual `r = measured - modeled` weighted by `inv_variance`, it
accumulates the whitened curvature `G = sqrt(Sa) * J^T Se^-1 J * sqrt(Sa)` and
gradient `b = sqrt(Sa) * J^T Se^-1 r`, plus the reflectance chi-square and the
unwhitened `J^T Se^-1 J` it keeps for the covariance step. The pressure-lane
Jacobian column is scaled by the altitude-pressure slope above before it enters
the sum.

`solveStep` takes one damped step. It diagonalizes the symmetric 2x2 `G` with a
closed-form Jacobi rotation (`algebra.jacobiEigenSymmetric`), rotates `b` and the
current offset into the eigenbasis, and updates each eigenmode with
Levenberg-Marquardt damping, `dx_k = (s * b_k + lambda_k * dx_k) / (lambda_k + 1)`
with `lambda_k = s * eigenvalue_k`. The damping scale `s` is a step factor
squared; if the resulting step is too large, the factor is cut by 0.75 and the
step retried, so `s` drops by 0.5625 each try and the step is flagged as outside
the trusted linear range, up to ten retries. The new physical state is
`prior + sqrt(Sa) * V * dx`, and the same eigensystem gives the posterior
precision in physical units.

The driver loop in `src/root.zig` then clamps the state to the lane bounds and
records the iteration. It converges when `quadraticForm(posterior_precision, dx)`
divided by the two lanes falls below the threshold and the last step stayed in the
linear range. After the loop, `invertSymmetric` turns the final precision into the
posterior covariance, and `multiply` forms the `averaging_kernel`, the covariance
times `J^T Se^-1 J`, which says how much of the answer comes from the measurement
rather than the prior.

## The 2x2 linear algebra (`algebra.zig`)

Because the state is fixed at two lanes, every matrix is 2x2 and every vector has
two entries. `algebra.zig` is that arithmetic, with no allocator and no dynamic
dispatch:

1. `choleskyLowerDiagonal` reduces to a per-lane square root, since `Sa` is
   diagonal: it returns `sqrt(Sa)` and `1/sqrt(Sa)`, rejecting a non-positive
   variance.
2. `jacobiEigenSymmetric` diagonalizes the symmetric `G` in one closed-form
   rotation, clamps the eigenvalues non-negative, and sorts them descending.
3. `invertSymmetric` inverts a 2x2 by cofactors, rejecting a near-singular
   determinant.
4. `matrixVector`, `transposeMatrixVector`, and `multiply` are the products the
   step, the covariance, and the averaging matrix need.

Everything is a fixed stack value passed and returned by value; the file is held
to that, with no allocator added unless the state count itself changes.

## Results and the run variants

`runOptimalEstimation` (in `src/root.zig`) returns a `Result`: the retrieved
state, its posterior covariance and `averaging_kernel`, and a per-iteration
history (the state, the chi-square split into its reflectance and state parts, the
convergence metric, and the linear-range flag). Three more entry points wrap it:

- `runOptimalEstimationCorrection` — exactly one step, for refining a state that
  is already close.
- `runOptimalEstimationBatch` — a loop over many starts that share one
  measurement and scene, each with its own initial and prior state. An
  out-of-memory error stops the batch; any other per-run error marks that run
  failed and the loop goes on.
- `runFastmodeOptimalEstimationBatch` — two stages, a cheap fit followed by a
  full-physics correction seeded with the cheap result.

`MeasuredReflectanceRows` holds the dense copy of one measurement, and the
`Result`, `BatchResult`, and `FastmodeBatchResult` owners, all defined here in
`retrieval/root.zig`, hold the arrays the C layer borrows back to Python. The
retrieval math itself allocates nothing.

## Warm memory across iterations

The forward pass is the cost; the optimal-estimation arithmetic is a handful of
2x2 operations. So a retrieval keeps the `SessionMemory` warm across every
iteration (the sampling table, the line cross-sections, the solar flux, the
per-worker scratch) and refreshes only what the new aerosol state changes.

Writing the state back into the scene moves the target interval's pressure
boundaries (the mid-pressure plus or minus half the layer thickness) and rebuilds
the small aerosol table. The vertical grid is refilled in place by
`refillFromPreparedProfiles` with no allocation, and the line cross-sections are
reused when the wavelengths and the mode bits match, so each iteration pays for
one forward pass and little else.

## Where to start

1. `root.zig`: `accumulateNormalSystem` and `solveStep`, one iteration end to end.
2. `algebra.zig`: the 2x2 eigensolve and inverse the step is built on.
3. `runOptimalEstimation` in `src/root.zig`: the loop that drives this folder.
4. the parent `src/README.md` for how the forward pass feeds each iteration, and
   `rtm/README.md` for where the Jacobians come from.
