"""
    QuantisedDiatomic

This module exports two user facing functions:

- `generate_configurations`
    Creates a set of velocities and positions for diatomic molecule with specified
    vibrational `ν` and rotational `J` quantum numbers.

- `quantise_diatomic`
    Obtains vibrational `ν` and rotational `J` quantum numbers for a diatomic molecule
    with a given set of velocities and positions.

The central concept of this module is the EBK procedure which is nicely detailed here:
[Larkoski2006](@cite)

Inspired by VENUS96: [Hase1996](@cite)
"""
module QuantisedDiatomic

using QuadGK: QuadGK
using Rotations: Rotations
using LinearAlgebra: norm, normalize!, nullspace, cross, I
using UnitfulAtomic: austrip
using Distributions: Uniform
using UnicodePlots: lineplot, lineplot!, DotCanvas, histogram
using Optim: Optim
using Roots: Roots
using TimerOutputs: TimerOutputs, @timeit
using Interpolations: interpolate, BSpline, Cubic, Line, OnGrid, scale, hessian

using NQCDynamics: Simulation, Calculators, DynamicsUtils, masses
using NQCBase: Atoms, PeriodicCell, InfiniteCell
using NQCModels: NQCModels
using NQCModels.AdiabaticModels: AdiabaticModel

export generate_configurations
export quantise_diatomic

const TIMER = TimerOutputs.TimerOutput()

include("energy_evaluation.jl")
include("binding_curve.jl")
include("random_configuration.jl")

struct EffectivePotential{T,B,F}
    μ::T
    J::Int
    binding_curve::BindingCurve{T,B,F}
end

function (effective_potential::EffectivePotential)(r)
    (;μ, J, binding_curve) = effective_potential
    rotational = J*(J+1) / (2μ*r^2)

    potential = binding_curve.fit(r)
    return rotational + potential
end

struct RadialMomentum{T,B,F}
    total_energy::T
    V::EffectivePotential{T,B,F}
end

function (radial_momentum::RadialMomentum)(r)
    (;total_energy, V) = radial_momentum
    return sqrt_avoid_negatives(2V.μ * (total_energy - V(r)))
end


"""
    generate_configurations(sim, ν, J; samples=1000, height=10, normal_vector=[0, 0, 1],
        translational_energy=0, direction=[0, 0, -1], position=[0, 0, height])

Generate positions and momenta for given quantum numbers

`translational_energy`, `direction` and `position` specify the kinetic energy in
a specific direction with the molecule placed with centre of mass at `position`.

Keyword arguments `height` and `normal_vector` become relevant if the potential
requires specific placement of the molecule.
These allow the molecule to be placed at a distance `height` in the direction
`normal_vector` when performing potential evaluations.
"""
function generate_configurations(sim, ν, J;
    samples=1000,
    height=10.0,
    surface_normal=[0, 0, 1.0],
    translational_energy=0.0,
    direction=[0, 0, -1.0],
    atom_indices=[1, 2],
    r=zeros(size(sim)),
    bond_lengths=0.5:0.01:5.0
)

    μ = reduced_mass(masses(sim)[atom_indices])
    _, slab = separate_slab_and_molecule(atom_indices, r)
    generation = GenerationParameters(direction, austrip(translational_energy), samples)
    environment = EvaluationEnvironment(atom_indices, size(sim), slab, austrip(height), surface_normal)

    binding_curve = calculate_binding_curve(bond_lengths, sim.calculator.model, environment)
    plot_binding_curve(binding_curve.bond_lengths, binding_curve.potential, binding_curve.fit)

    V = EffectivePotential(μ, J, binding_curve)

    total_energy, bounds = find_total_energy(V, ν)

    radial_momentum = RadialMomentum(total_energy, V)
    bonds, momenta = select_random_bond_lengths(bounds, radial_momentum, samples)
    velocities = momenta ./ μ

    plot_distributions(bonds, velocities)

    @info "Generating the requested configurations..."
    configure_diatomic.(sim, bonds, velocities, J, environment, generation, μ)
end

function generate_1D_vibrations(model::AdiabaticModel, μ::Real, ν::Integer;
    samples=1000, bond_lengths=0.5:0.01:5.0
)

    J = 0
    environment = EvaluationEnvironment([1], (1,1), zeros(1,0), 0.0, [1.0])
    binding_curve = calculate_binding_curve(bond_lengths, model, environment)
    plot_binding_curve(binding_curve.bond_lengths, binding_curve.potential, binding_curve.fit)

    V = EffectivePotential(μ, J, binding_curve)

    total_energy, bounds = find_total_energy(V, ν)

    radial_momentum = RadialMomentum(total_energy, V)
    bonds, momenta = select_random_bond_lengths(bounds, radial_momentum, samples)
    velocities = momenta ./ μ

    plot_distributions(bonds, velocities)

    return bonds, velocities
end

"""
    sqrt_avoid_negatives(x)

Same as `sqrt` but returns `zero(x)` if `x` is negative.
Used here just in case the endpoints are a little off.
"""
function sqrt_avoid_negatives(x)
    if x < zero(x) 
        @warn """
        `sqrt(x)` of negative number attempted: x = $x, returning zero instead.\
        This is acceptable if x is very close to zero. Otherwise something has gone wrong.
        """
        return zero(x)
    else
        return sqrt(x)
    end
end

"""
    find_total_energy(V::EffectivePotential, ν)

Returns the energy associated with the specified quantum numbers
"""
function find_total_energy(V::EffectivePotential, ν)

    μ = V.μ
    k = calculate_force_constant(V.binding_curve)
    E = guess_initial_energy(k, μ, ν, V.binding_curve.potential_minimum)

    "Evaluate vibrational quantum number."
    function nᵣ(E, r₁, r₂)
        kernel(r) = sqrt_avoid_negatives(E - V(r))
        integral, _ = QuadGK.quadgk(kernel, r₁, r₂; maxevals=100)
        return sqrt(2μ)/π * integral - 1/2
    end

    "Derivative of the above"
    function ∂nᵣ∂E(E, r₁, r₂)
        kernel(r) = 1 / sqrt_avoid_negatives(E - V(r))
        integral, _ = QuadGK.quadgk(kernel, r₁, r₂; maxevals=100)
        return sqrt(2μ)/2π * integral
    end

    "Second derivative of the above"
    function ∂²nᵣ∂E²(E, r₁, r₂)
        kernel(r) = 1 / sqrt_avoid_negatives(E - V(r))^3
        integral, _ = QuadGK.quadgk(kernel, r₁, r₂; maxevals=100)
        return -sqrt(2μ)/4π * integral
    end

    """
    Evaluates the function, gradient and hessian as described in the Optim documentation.
    """
    function fgh!(F,G,H,x)
        E = x[1]
        r₁, r₂ = find_integral_bounds(E, V)

        νtmp = nᵣ(E, r₁, r₂)
        difference = νtmp - ν

        if G !== nothing
            G[1] = ∂nᵣ∂E(E, r₁, r₂) * sign(difference)
        end
        if H !== nothing
            H[1] = ∂²nᵣ∂E²(E, r₁, r₂) * sign(difference)
        end
        if F !== nothing
            return abs(difference)
        end
    end

    @info "Converging the total energy to match the chosen quantum numbers..."
    optim = Optim.optimize(Optim.only_fgh!(fgh!), [E], Optim.Newton(),
        Optim.Options(show_trace=true, x_tol=1e-3)
    )
    E = Optim.minimizer(optim)[1]
    bounds = find_integral_bounds(E, V)

    E, bounds
end

function find_integral_bounds(total_energy::Real, V::EffectivePotential)
    energy_difference(r) = total_energy - V(r)

    r₀ = V.binding_curve.equilibrium_bond_length
    minimum_bond_length = first(V.binding_curve.bond_lengths)
    maximum_bond_length = last(V.binding_curve.bond_lengths)
    r₁ = @timeit TIMER "Lower bound" Roots.find_zero(energy_difference, (minimum_bond_length, r₀))
    r₂ = @timeit TIMER "Upper bound" Roots.find_zero(energy_difference, (r₀, maximum_bond_length))

    return r₁, r₂
end

"""
    quantise_diatomic(sim::Simulation, v::Matrix, r::Matrix;
        height=10, normal_vector=[0, 0, 1])

Quantise the vibrational and rotational degrees of freedom for the specified
positions and velocities

When evaluating the potential, the molecule is moved to `height` in direction `normal_vector`.
If the potential is independent of centre of mass position, this has no effect.
Otherwise, be sure to modify these parameters to give the intended behaviour.
"""
function quantise_diatomic(sim::Simulation, v::Matrix, r::Matrix;
    height=10.0, surface_normal=[0, 0, 1.0], atom_indices=[1, 2],
    show_timer=false, reset_timer=false,
    bond_lengths=0.5:0.01:5.0
)

    reset_timer && TimerOutputs.reset_timer!(TIMER)

    r, slab = separate_slab_and_molecule(atom_indices, r)
    environment = EvaluationEnvironment(atom_indices, size(sim), slab, austrip(height), surface_normal)

    r_com = subtract_centre_of_mass(r, masses(sim)[atom_indices])
    v_com = subtract_centre_of_mass(v, masses(sim)[atom_indices])
    p_com = v_com .* masses(sim)[atom_indices]'

    k = DynamicsUtils.classical_kinetic_energy(sim, v_com)
    p = calculate_diatomic_energy(bond_length(r_com), sim.calculator.model, environment)
    E = k + p

    L = total_angular_momentum(r_com, p_com)
    J = round(Int, (sqrt(1+4*L^2) - 1) / 2) # L^2 = J(J+1)ħ^2

    μ = reduced_mass(masses(sim)[atom_indices])

    binding_curve = calculate_binding_curve(bond_lengths, sim.calculator.model, environment)

    V = EffectivePotential(μ, J, binding_curve)

    r₁, r₂ = @timeit TIMER "Finding bounds" find_integral_bounds(E, V)

    function nᵣ(E, r₁, r₂)
        kernel(r) = sqrt_avoid_negatives(E - V(r))
        integral, _ = QuadGK.quadgk(kernel, r₁, r₂; maxevals=100)
        return sqrt(2μ)/π * integral - 1/2
    end

    ν = @timeit TIMER "Calculating ν" nᵣ(E, r₁, r₂)

    TimerOutputs.complement!(TIMER)
    show_timer && show(TIMER)

    return round(Int, ν), J
end

function quantise_1D_vibration(model::AdiabaticModel, μ::Real, r::Real, v::Real;
    bond_lengths=0.5:0.01:5.0, reset_timer=false, show_timer=false
)
    reset_timer && TimerOutputs.reset_timer!(TIMER)

    environment = EvaluationEnvironment([1], (1,1), zeros(1,0), 0.0, [1.0])

    kinetic_energy = μ * v^2 / 2
    potential_energy = calculate_diatomic_energy(r, model, environment)
    E = kinetic_energy + potential_energy
    J = 0

    binding_curve = calculate_binding_curve(bond_lengths, model, environment)

    V = EffectivePotential(μ, J, binding_curve)

    r₁, r₂ = @timeit TIMER "Finding bounds" find_integral_bounds(E, V)

    function nᵣ(E, r₁, r₂)
        kernel(r) = sqrt_avoid_negatives(E - V(r))
        integral, _ = QuadGK.quadgk(kernel, r₁, r₂; maxevals=100)
        return sqrt(2μ)/π * integral - 1/2
    end

    ν = @timeit TIMER "Calculating ν" nᵣ(E, r₁, r₂)

    TimerOutputs.complement!(TIMER)
    show_timer && show(TIMER)

    return round(Int, ν)
end

subtract_centre_of_mass(x, m) = x .- centre_of_mass(x, m)
@views centre_of_mass(x, m) = (x[:,1].*m[1] .+ x[:,2].*m[2]) ./ (m[1]+m[2])
reduced_mass(atoms::Atoms) = reduced_mass(atoms.masses)

function reduced_mass(m::AbstractVector)
    if length(m) == 1
        return m[1]
    elseif length(m) == 2
        m[1]*m[2]/(m[1]+m[2])
    else
        throw(error("Mass vector of incorrect length."))
    end
end

@views bond_length(r) = norm(r[:,1] .- r[:,2])
@views total_angular_momentum(r, p) = norm(cross(r[:,1], p[:,1]) + cross(r[:,2], p[:,2]))

end # module
