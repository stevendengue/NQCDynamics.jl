using Test
using NonadiabaticMolecularDynamics
using NonadiabaticMolecularDynamics.InitialConditions
using Unitful
using StatsBase

atoms = Atoms{Float64}([:H, :H, :C])
cell = PeriodicCell(hcat(1))
model = Models.Harmonic()

Δ = Dict([(:H, 0.1), (:C, 0.1)])
monte_carlo = MonteCarlo{Float64}(Δ, length(atoms), 100, Int[], x->true)
sim = Simulation(1, 100u"K", cell, atoms, model, monte_carlo)

@testset "propose_move!" begin
    Rᵢ = zeros(sim.DoFs, length(sim.atoms))
    Rₚ = zero(Rᵢ)
    @test Rᵢ == Rₚ
    MetropolisHastings.propose_move!(sim, monte_carlo, Rᵢ, Rₚ, 1)
    @test Rᵢ != Rₚ
end

@testset "assess_proposal!" begin
    Rᵢ = randn(sim.DoFs, length(sim.atoms))
    Rₚ = zero(Rᵢ)
    # Accept the move
    sim.method.Eᵢ = 1
    output = MetropolisHastings.MonteCarloOutput(Rᵢ, sim.atoms)
    MetropolisHastings.assess_proposal!(sim, monte_carlo, Rᵢ, Rₚ, output, 1)
    @test output.R[1] == Rₚ
    # Reject the move
    sim.method.Eᵢ = -1
    MetropolisHastings.assess_proposal!(sim, monte_carlo, Rᵢ, Rₚ, output, 1)
    @test output.R[1] == Rᵢ
end

@testset "write_output!" begin
    Rₚ = fill(0.1, sim.DoFs, length(sim.atoms))
    output = InitialConditions.MetropolisHastings.MonteCarloOutput(Rₚ, sim.atoms)
    MetropolisHastings.write_output!(output, Rₚ, 1.0)
    Rₚ .+= 1
    MetropolisHastings.write_output!(output, Rₚ, 1.1)
    @test all(output.R[1] .== 0.1)
    @test output.energy[1] == 1.0
    @test all(output.R[2] .== 1.1)
    @test output.energy[2] == 1.1
end

@testset "acceptance_probability" begin
    e1 = 0.0
    e2 = -0.001
    @test MetropolisHastings.acceptance_probability(e2, e1, 1.0) == 1
    e1 = 0.0
    e2 = 0.001
    @test 1 > MetropolisHastings.acceptance_probability(e2, e1, 1.0) > 0
    e1 = 0.0
    e2 = Inf
    @test MetropolisHastings.acceptance_probability(e2, e1, 1.0) == 0
end

@testset "run_monte_carlo_sampling" begin
    R0 = rand(sim.DoFs, length(sim.atoms))
    out = InitialConditions.run_monte_carlo_sampling(sim, R0, Δ, 10)
    @test !(out.R[1] ≈ out.R[10])
    @test !(out.energy[1] ≈ out.energy[20])
end

@testset "propose_centroid_move!" begin
    monte_carlo = PathIntegralMonteCarlo{Float64}(Δ, length(atoms), 100, [1], 1.0, 10)
    sim = RingPolymerSimulation(1, 100u"K", cell, atoms, model, monte_carlo, 10, [:H])
    Rᵢ = randn(3, length(sim.atoms), 10)
    Rₚ = copy(Rᵢ)
    MetropolisHastings.propose_centroid_move!(sim, monte_carlo, Rᵢ, Rₚ, 2)
    @test mean(Rₚ[:,1,:]) ≈ mean(Rᵢ[:,1,:]) # Check fixed atom does not move
    
    transform_to_normal_modes!(sim.beads, Rₚ)
    transform_to_normal_modes!(sim.beads, Rᵢ)
    @test !(Rₚ[:,:,1] ≈ Rᵢ[:,:,1]) # Test centroid has moved
    @test Rₚ[:,1:2,2:end] ≈ Rᵢ[:,1:2,2:end] # Test only centroid moves for quantum atoms
end
