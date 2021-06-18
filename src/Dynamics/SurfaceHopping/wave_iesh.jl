using StatsBase: mean
using .Calculators: DiabaticCalculator, RingPolymerDiabaticCalculator

export wave_IESH
export SurfaceHoppingVariablesIESH
export get_wavefunction_matrix

"""This module controles how IESH is executed. For a description of IESH, see e.g.
Roy, Shenvi, Tully, J. Chem. Phys. 130, 174716 (2009) and 
Shenvi, Roy, Tully, J. Chem. Phys. 130, 174107 (2009).

The density matrix is set up in surface_hopping_variables.jl
"""

abstract type SurfaceHoppingIESH <: Method end

mutable struct wave_IESH{T} <: SurfaceHoppingIESH
    wavefunction_propagator::Matrix{Complex{T}}
    hopping_probability::Vector{T}
    new_state::Vector{Int}
    function wave_IESH{T}(states::Integer) where {T}

    
        wavefunction_propagator = zeros(states, states)
        hopping_probability = zeros(3)
        new_state = zeros(states) # this probably needs to be modified
        new{T}(wavefunction_propagator, hopping_probability, new_state)
    end
end

# Define for wave function propagation in IESH. It might be possible to unite this w/ the top
mutable struct SurfaceHoppingVariablesIESH{T,D,S}  <: DynamicalVariables{T}
    x::ArrayPartition{Complex{T}, Tuple{D,D,Matrix{Complex{T}}}}
    state::S
end

function SurfaceHoppingVariablesIESH(x::ArrayPartition{T}, state) where {T<:AbstractFloat}
    SurfaceHoppingVariablesIESH(ArrayPartition(x.x[1], x.x[2], Complex.(x.x[3])), state)
end

"""Set up matrix that stores wave vectors for propagation
See ShenviRoyTully_JChemPhys_130_174107_200
Note that different from the density matrix, wave_mat defines vectors for a state, 
where 1 indicated the state, but not whether occupied or not."""
function SurfaceHoppingVariablesIESH(v::AbstractArray, r::AbstractArray, n_states::Integer, state::Vector{Int})
    wave_mat = zeros(Complex{eltype(r)}, n_states, Int(n_states/2))
    #for i=1:n_states/2
    for i=1:n_states/2
        wave_mat[Int(i), Int(i)] = 1
    end
    SurfaceHoppingVariablesIESH(ArrayPartition(v, r, wave_mat), state)
end

get_wavefunction_matrix(u::SurfaceHoppingVariablesIESH) = u.x.x[3]

"""motion! is given to ODE Problem and propagated by the timestep there"""
function motion!(du, u, sim::AbstractSimulation{<:SurfaceHoppingIESH}, t)
    #println("ping1")
    dr = get_positions(du)
    dv = get_velocities(du)
    dσ = get_wavefunction_matrix(du)


    r = get_positions(u)
    v = get_velocities(u)
    σ = get_wavefunction_matrix(u)

    # presumably comes from DifferentialEquations-Julia module
    velocity!(dr, v, r, sim, t)
    # src/Calculators/Calculators.jl
    # Gets energy, forces, eigenvalues and nonadiabatic couplings.
    Calculators.update_electronics!(sim.calculator, r) # uses only nuclear DOF
    acceleration!(dv, v, r, sim, t; state=u.state) # nuclear DOF
    set_wavefunction_derivative!(dσ, v, σ, sim, u)
end


"""This is part of the adiabatic propagation of the nuclei.
   See Eq. 12 of Shenvi, Tully JCP 2009 paper."""
function acceleration!(dv, v, r, sim::Simulation{<:wave_IESH}, t; state=1)
    #println("ping2")
    # Goes over direction 2
    dv .= 0.0
    for i in axes(dv, 2)
        for j in axes(dv, 1)        
            for k in 1:length(state)
                # Include only occupied state.
                # It's kind of double with *state[k].
                if state[k] == 1
                    # Calculate as the sum of the momenta of occupied states
                    dv[j,i] = dv[j,i] - sim.calculator.adiabatic_derivative[j,i][k, k]*
                              state[k] / sim.atoms.masses[i]
                end
            end
        end
    end
    return nothing
end

"""Propagation of electronic wave function happens according to Eq. (14) 
   in the Shenvi, Tully paper (JCP 2009)
   The extended formula is taken from HammesSchifferTully_JChemPhys_101_4657_1994, Eq. (16):
   iħ d ψ_{j}/dt = ∑_j ψ_{m}(V_{jm} - i v d_{jm})
   Where v is the velocity. See also Tully_JChemPhys_93_1061_1990, Eq. (7). 
   For the IESH case, since each electron is treated independently, the equation
   above needs to be evaluated for each electron, so it becomes:
   iħ d ψ^{K}_j/dt =  V_{j,j}ψ^{K}_j - i v ∑_m d_{m,j}*ψ^{K}_m)
   K is the number of the electron and 
   j, m run over the number of states
   """
function set_wavefunction_derivative!(dσ, v, σ, sim::Simulation{<:SurfaceHoppingIESH}, u)
    V = sim.calculator.eigenvalues
    d = sim.calculator.nonadiabatic_coupling
    # # This is slower
    # @views for i in axes(dσ, 2)       
    #     set_single_electron_derivative!(dσ[:,i], σ[:,i], V, v, d)
    # end
    @views for i in axes(dσ, 2) 
         @. dσ[:,i] = -im*V * σ[:,i]
        # goes over number of states
        for m in 1:length(σ[:,i])
        # eachindex(v) is here going over the DOF and the number of atoms
        for I in eachindex(v)
            dσ[:,i] .-= v[I]*d[I][:,m]*σ[m,i]
            #println(m, " ", v[I], " ", d[I][:,m], " ",cK[m], " ",v[I]*d[I][:,m]*cK[m])
            end
        end
    end
end

#This is slower compared to implementing it directly in set_wavefunction_derivative!
# function set_single_electron_derivative!(dc, cK, V, v, d)
#     # Element times element product.
#     #@. dc = -im*V * c
#     @. dc = -im*V * cK
#     # goes over number of states
#     for m in 1:length(cK)
#         # eachindex(v) is here going over the DOF and the number of atoms
#         for I in eachindex(v)
#             dc .-= v[I]*d[I][:,m]*cK[m]
#             #println(m, " ", v[I], " ", d[I][:,m], " ",cK[m], " ",v[I]*d[I][:,m]*cK[m])
#         end
#     end
#     return nothing
# end

function check_hop!(u, t, integrator)::Bool
    #println("ping4")
    #@time begin
    evaluate_hopping_probability!(
        integrator.p,
        u,
        get_proposed_dt(integrator))

    integrator.p.method.new_state = select_new_state(integrator.p, u)
    #end
    return integrator.p.method.new_state != u.state
end

"""Hopping probability according to Eq.s (21), (17), (18) in Shenvi/Roy/Tully JCP 2009 paper.
   The density matrix is used there:
   σ_{i,j} = ∑_K c_{K,i}*c_{K,j}^*
   K is the index of the independent electrons
   i,j are the electronic states.
   The equation for the hopping probability is:
   g_{k,j} = Max(\frac{-2 Real(σ_{k,j} v d_{j,k})}{σ_{k,k}})
   """
function evaluate_hopping_probability!(sim::Simulation{<:wave_IESH}, u, dt)
    #println("ping6")
    v = get_velocities(u)
    Ψ = get_wavefunction_matrix(u)
    s = u.state
    d = sim.calculator.nonadiabatic_coupling
    n_states = sim.calculator.model.n_states

    hop_mat = zeros(n_states, n_states)
    #sim.calculator.tmp_mat_complex1 .= 0
    sumer = 0
    first = true
    random_number = rand()
    sum_before = 0.0
    sim.method.hopping_probability .= 0 # Set all entries to 0
    σlm = 0
    σll = 0

    for l = 1:n_states
        # Is occupied?
        if(s[l] == 1)
            for m = 1:n_states
                # Is unoccupied?
                if (s[m] == 0)
                    σlm = 0
                    σll = 0
                    for I in eachindex(v)
                        for k = 1:Int(n_states/2)
                            σlm = σlm + Ψ[m,k]*conj(Ψ[l,k])
                            σll = σll + Ψ[l,k]*conj(Ψ[l,k])
                        end
                            hop_mat[l,m] = hop_mat[l,m] + 2*v[I]*real(σlm*
                                           d[I][m,l] * dt)/σll
                    end
                end # end if 
                clamp(hop_mat[l,m], 0, 1)
                # Calculate the hopping probability. Hopping occures for
                # the transition that's first above the random number.
                sumer = sumer + abs(hop_mat[l,m]) # cumulative sum.
                # If sum of hopping probabilities is larger than random number,
                # hopping can occur
                if (random_number > sumer && first)
                    sum_before = sumer
                elseif (random_number < sumer && random_number > sum_before && first)
                    sim.method.hopping_probability[1] = sumer
                    sim.method.hopping_probability[2] = l
                    sim.method.hopping_probability[3] = m
                    first = false
                elseif (sumer > 1 && first)
                    println("Warning: Sum of hopping probability above 1!")
                    println("Sum: ", sumer, " Individ. hopping probability: ", hop_mat[l,m])
                    println("l = ", l, " m = ", m)
                    println(first)
                end
            end
        end
    end
    return nothing
end

"""
Set up new states for hopping
"""
function select_new_state(sim::AbstractSimulation{<:wave_IESH}, u)
    #println("ping7")
    if sim.method.hopping_probability[1] !=0
        println("Hop! from ", Int(sim.method.hopping_probability[2]), " to ", Int(sim.method.hopping_probability[3]))
        # Set new state population
        new_state = copy(u.state)
        new_state[Int(sim.method.hopping_probability[2])] = 0
        new_state[Int(sim.method.hopping_probability[3])] = 1
        return new_state
    end
    return u.state
end

function execute_hop!(integrator)
    #println("ping8")
    rescale_velocity!(integrator.p, integrator.u) && (integrator.u.state = integrator.p.method.new_state)
    return nothing
end

function rescale_velocity!(sim::AbstractSimulation{<:wave_IESH}, u)::Bool
    #println("ping9")
    old_state = u.state
    new_state = sim.method.new_state
    state_diff = sim.method.hopping_probability
    velocity = get_velocities(u)
    
    # Loop over and sum over potential energies, according to Eq. 12 Shenvi, Roy,  Tully,J. Chem. Phys. 130, 174107 (2009)
    c = 0
    for i=1:length(old_state)
        c = c + calculate_potential_energy_change(sim.calculator, 
                                                  new_state[i], old_state[i], i)
    end
    a, b = evaluate_a_and_b(sim, velocity, state_diff)
    discriminant = b.^2 .- 2a.*c
    
    any(discriminant .< 0) && println("Frustrated!")
    any(discriminant .< 0) && return false

    root = sqrt.(discriminant)
    velocity_rescale = min.(abs.((b .+ root) ./ a), abs.((b .- root) ./ a))
    perform_rescaling!(sim, velocity, velocity_rescale, state_diff)

    return true
end

"""
Evaluate nonadiabatic coupling after hop
"""
function evaluate_a_and_b(sim::AbstractSimulation{<:wave_IESH}, velocity::AbstractArray, state_diff)
    #println("ping10")
    a = zeros(length(sim.atoms))
    b = zero(a)
    @views for i in range(sim.atoms)
        coupling = [sim.calculator.nonadiabatic_coupling[j,i][Int(state_diff[3]), 
                    Int(state_diff[2])] for j=1:sim.DoFs]
        a[i] = coupling'coupling / sim.atoms.masses[i]
        b[i] = velocity[:,i]'coupling
    end
    return (a, b)
end


"""
Performs momentum rescaling, see eq. 7 and 8 SubotnikBellonzi_AnnuRevPhyschem_67_387_2016
"""
function perform_rescaling!(sim::Simulation{<:wave_IESH}, velocity, velocity_rescale,
                            state_diff)
    #println("ping11")
    for i in range(sim.atoms)
        coupling = [sim.calculator.nonadiabatic_coupling[j,i][Int(state_diff[3]), 
                    Int(state_diff[2])] for j=1:sim.DoFs]
        velocity[:,i] .-= velocity_rescale[i] .* coupling ./ sim.atoms.masses[i]
    end
    return nothing
end

# Goes to rescale_velocity!
function calculate_potential_energy_change(calc::DiabaticCalculator, new_state::Integer, 
                                           current_state::Integer, counter::Integer)
    #println("ping12")
    #DeltaE = calc.eigenvalues[counter]*new_state - calc.eigenvalues[counter]*current_state
    return calc.eigenvalues[counter]*new_state - calc.eigenvalues[counter]*current_state
end


const HoppingCallback = DiscreteCallback(check_hop!, execute_hop!; save_positions=(false, false))
get_callbacks(::AbstractSimulation{<:SurfaceHoppingIESH}) = HoppingCallback

"""
This function should set the field `sim.method.hopping_probability`.
"""
function evaluate_hopping_probability!(::AbstractSimulation{<:SurfaceHoppingIESH}, u, dt) end

"""
This function should return the desired state determined by the probability.
Should return the original state if no hop is desired.
"""
function select_new_state(::AbstractSimulation{<:SurfaceHoppingIESH}, u) end

"""
This function should modify the velocity and return a `Bool` that determines
whether the state change should take place.

This only needs to be implemented if the velocity should be modified during a hop.
"""
rescale_velocity!(::AbstractSimulation{<:SurfaceHoppingIESH}, u) = true

create_problem(u0, tspan, sim::AbstractSimulation{<:SurfaceHoppingIESH}) = 
               ODEProblem(motion!, u0, tspan, sim)

function impurity_summary(model::DiabaticModel, R::AbstractMatrix, state::AbstractArray, σ::AbstractArray)
    """Calculate impurity population according to MiaoSubotnik_JChemPhys_150_041711_2019"""

    eig_vec = zeros(model.n_states,model.n_states)

    eival = zeros(model.n_states)
    σad = zeros(Complex, model.n_states, model.n_states)
    tmp = 0
    σdia = zeros(Complex, model.n_states, model.n_states)
    eig_array = zeros(4+model.n_states)
    V = Hermitian(zeros(model.n_states,model.n_states))
    dvect = zeros(model.n_states)
    dvect[2] = 1
    
    # get potential
    potential!(model,V,R)
    eig_vec .= eigvecs(V)
    ieig = inv(eig_vec)
    # Get density matrix matrix
    for i = 1:length(state)
        eig_array[4 + i] = norm(σ[i,:])
        for j = 1:length(state)
            for k in axes(σ,2)
                σad[i,j] = σad[i,j] + σ[i,k]*σ[j,k]
            end
        end
    end


    #Turn into diabatic matrix for impurity population
    σdia .= eig_vec *σad * ieig
    eig_array[4] = real(σdia[2,2])^2 + imag(σdia[2,2])^2

    # eig_array[4] = 0
    # for k in axes(σ,2)
    #     for i = 1:length(state)
    #         σad[i,i] = σ[i,k]
    #     end
    #     σdia .= 0
    #     σdia .= eig_vec *σad * ieig
    #     eig_array[4] = eig_array[4] + real(σdia[2,2])^2 + imag(σdia[2,2])^2
    # end
    

    # Get the eigenvectors and values
    eival .= eigvals(V)

    # save position
    eig_array[1] = R[1]
    for i = 1:length(state)
        # Energy
        eig_array[2] = eig_array[2] + state[i]*eival[i]
        # Hopping prob. by hopping array
        eig_array[3] = eig_array[3] + state[i]
        
    end

    # # over electrons. This is adiabatic.
    # for i in axes(σ, 2)
    #     eig_array[4] = eig_array[4] + real(σ[2,i])^2 + imag(σ[2,i])^2
    # end

    # Export an array of eigenvalues with last two elements being hopping prob
    eig_array = eig_array
end
