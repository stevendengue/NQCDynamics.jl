# [Classical molecular dynamics](@id classical-dynamics)

Classical (molecular) dynamics proceeds
by solving the dynamics for a system governed by a classical Hamiltonian containing
the kinetic energy of the particles and a potential energy function:

```math
H = \frac{P^2}{2M} + V(R)
```

To integrate the equations we use the `VelocityVerlet()` algorithm from
`DifferentialEquations.jl`, which is one of the most widely used
algorithms for molecular dynamics.

## Example

We can create two particles with `mass = 1` and attach a `DiatomicHarmonic` interaction which provides a harmonic interatomic potential.

!!! note

    Recall that the constructor for `Simulation(...)` when called without a type
    parameter as below defaults to `Simulation{Classical}(...)`.

```@example
using NQCDynamics
using Plots

sim = Simulation(Atoms([1, 1]), DiatomicHarmonic())
v = rand(3, 2)
u0 = DynamicsVariables(sim, zeros(3, 2), hcat(randn(3), randn(3).+1))

traj = run_trajectory(u0, (0.0, 1e2), sim; dt=0.1, output=(:position))

plot(traj, :position)
```
