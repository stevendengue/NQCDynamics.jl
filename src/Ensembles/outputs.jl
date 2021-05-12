using Unitful
using UnitfulAtomic
using LinearAlgebra: norm
using ..InitialConditions.QuantisedDiatomic

abstract type AbstractOutput end

"""
$(TYPEDEF)

Output the end point of each trajectory.
"""
struct OutputFinal <: AbstractOutput end

(::OutputFinal)(sol, i) = (last(sol), false)

"""
$(TYPEDEF)

Output a 1 if the molecule has dissociated, 0 otherwise.

$(FIELDS)
"""
struct OutputDissociation{T,A} <: AbstractOutput
    "The maximum distance at which the two atoms can be considered bonded."
    distance::T
    "The indices of the two atoms in the molecule of interest."
    atom_indices::A
end
OutputDissociation(distance::Unitful.Quantity, atom_indices) = OutputDissociation(austrip(distance), atom_indices)

function (output::OutputDissociation)(sol, i)
    R = Dynamics.get_positions(last(sol))
    dissociated = norm(R[:,output.atom_indices[1]] .- R[:,output.atom_indices[2]]) > output.distance
    return dissociated ? (1, false) : (0, false)
end


"""
$(TYPEDEF)

Output the population of each diabatic state.
"""
struct OutputDiabaticPopulation{S} <: AbstractOutput
    sim::S
end
(output::OutputDiabaticPopulation)(sol, i) = (Dynamics.get_population.(output.sim, sol.u), false)

"""
$(TYPEDEF)

Output the vibrational and rotational quantum numbers of the final image.
"""
struct OutputQuantisedDiatomic{S,H,V} <: AbstractOutput
    sim::S
    height::H
    normal_vector::V
end
OutputQuantisedDiatomic(sim; height=10, normal_vector=[0, 0, 1]) = OutputQuantisedDiatomic(sim, height, normal_vector)

function (output::OutputQuantisedDiatomic)(sol, i)
    final = last(sol.u) 
    ν, J = QuantisedDiatomic.quantise_diatomic(output.sim,
        Dynamics.get_velocities(final), Dynamics.get_positions(final);
        height=output.height, normal_vector=output.normal_vector)
    return ((ν, J), false)
end