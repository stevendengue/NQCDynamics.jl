# [Thermal Metropolis-Hastings Monte Carlo](@id mhmc-sampling)

Metropolis-Hastings Monte Carlo is a popular method for sampling the canonical
distribution for a molecular system.
Our implementations uses [`AdvancedMH.jl`](https://github.com/TuringLang/AdvancedMH.jl)
from the [Turing](https://turing.ml/stable/) organisation.

For a classical `Simulation`, the algorithm involves proposing new configurations in a
random walk starting from an initial configuration.
These are accepted or rejected based upon the Metropolis-Hastings criteria.
The result is a Markov chain that samples the canonical distribution.

## Example

We can perform the sampling by setting up a classical simulation in the usual way and
providing an appropriate initial configuration.

```@example mh
using NQCDynamics
sim = Simulation(Atoms([:H, :H, :H, :H, :H]), Harmonic(); temperature=15)
r0 = zeros(size(sim))
```

Then we must also specify the total number of steps and the size of each step.
These can be provided in a dictionary for each species to allow for different step
sizes depending on the element in the simulation.
```@example mh
steps = 1e4
step_size = Dict(:H=>1)
```

Now we can run the sampling. The extra keyword argument `move_ratio` is used to specify
the fraction of the system moved during each Monte Carlo step.
If we attempt to move the entire system at once, we can expect a very low acceptance ratio,
whereas is we move only a single atom, the sampling will take much longer.
You will likely have to experiment with this parameter to achieve optimal sampling.
```@example mh
using NQCDynamics.InitialConditions: ThermalMonteCarlo
chain = ThermalMonteCarlo.run_advancedmh_sampling(sim, r0, steps, step_size; move_ratio=0.5)
```

Now that our sampling is complete we can evaluate the potential energy expectation value.
Here we use the [`@estimate`](@ref Estimators.@estimate) macro which will evaluate the
given function for every configuration inside `chain` and return the average.
Here we can see that the energy we obtain closely matches that predicted by the
equipartition theorem.
```@repl mh
Estimators.@estimate potential_energy(sim, chain)
sim.temperature / 2 * 5
```

## Legacy version

Prior to the use of [`AdvancedMH.jl`](https://github.com/TuringLang/AdvancedMH.jl),
an alternative version of the algorithm was implemented that works for both classical
and ring polymer systems.
This is currently still included in the code but should be regarded as deprecated and
will likely be removed/combined with the [`AdvancedMH.jl`](https://github.com/TuringLang/AdvancedMH.jl)
version.

Here, we use the legacy version to obtain a thermal distribution in a simple
model system.

```@setup monte
using NQCDynamics
using Plots
```
First we set up the system in the usual way, here we're using an NO molecule with
a harmonic interaction between the atoms.
Notice that we use `Unitful.jl` to specify the temperature.
```@example monte
using Unitful

atoms = Atoms([:N, :O])
model = DiatomicHarmonic(1.0)

sim = Simulation{Classical}(atoms, model; temperature=300u"K")
nothing # hide
```

Then we have to specify the parameters for the Monte Carlo simulation and perform the sampling.
`Δ` contains the step sizes for each of the species, `R0` the initial geometry and `passes` the
number of monte carlo passes we perform (`passes*n_atoms` steps total).
```@example monte
Δ = Dict([(:N, 0.1), (:O, 0.1)])
R0 = [1.0 0.0; 0.0 0.0; 0.0 0.0]
passes = 1000
output = InitialConditions.MetropolisHastings.run_monte_carlo_sampling(sim, R0, Δ, passes)
nothing # hide
```

Output has three fields: the acceptance rates for each species and the energies and geometries
obtained during sampling.
```@repl monte
output.acceptance
```
```@example monte
plot(output.energy)
xlabel!("Step") # hide
ylabel!("Energy") # hide
```

We can calculate the distance between each atom and plot the bond length throughout the sampling.
```@example monte
using LinearAlgebra
plot([norm(R[:,1] .- R[:,2]) for R in output.R])
xlabel!("Step") # hide
ylabel!("Bond length") # hide
```

The result of this simulation seamlessly interfaces with the `DynamicalDistribution`
presented in the previous section and `output.R` can be readily passed to provide
the position distribution.
The Monte Carlo sampling does not include velocities but these can be readily
obtained from the Maxwell-Boltzmann distribution.
