# Open Questions

## RTM Plus Jacobian Wall

The slow retained case still spends about one second per RTM+jacobian
iteration even with session reuse. The session helps, but repeated
RTM+jacobian work remains the retrieval elapsed time.

## Jacobian Internals

The retrieval-facing Jacobian is state-vector sized. Some lower Rust layers still
use fixed internal storage. There may be more latency available if derivative
state masks remove more internal work rather than only compacting the public
result.

## Surface Albedo

Surface albedo is fixed in the current aerosol-only retrieval. If it becomes a
retrieved parameter, it should be added to the `StateVector`, requested in
`jacobian_state_names`, and measured as a separate retrieval mode.

## Throughput Mode

The current baseline uses one zdisamar retrieval process at a time, letting each
retrieval use the model's internal workers. A future throughput mode could cap
internal workers per retrieval and run multiple retrievals concurrently, but that
is a different benchmark question.
