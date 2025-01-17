
struct BindingCurve{T,B,F}
    bond_lengths::B
    potential::Vector{T}
    equilibrium_bond_length::T
    potential_minimum::T
    fit::F
end

function calculate_binding_curve(
    bond_lengths::AbstractVector, model::AdiabaticModel, environment::EvaluationEnvironment
)
    potential = calculate_diatomic_energy.(bond_lengths, model, environment) # Calculate binding curve
    potential_minimum, index = findmin(potential)
    equilibrium_bond_length = bond_lengths[index]
    fit = fit_binding_curve(bond_lengths, potential)
    return BindingCurve(bond_lengths, potential, equilibrium_bond_length, potential_minimum, fit)
end

function fit_binding_curve(bond_lengths, binding_curve)
    itp = interpolate(binding_curve, BSpline(Cubic(Line(OnGrid()))))
    sitp = scale(itp, bond_lengths)
    return sitp
end

function calculate_force_constant(binding_curve)
    return hessian(binding_curve.fit, binding_curve.equilibrium_bond_length)[1]
end

function guess_initial_energy(k, μ, ν, potential_minimum)
    ω = sqrt(k / μ)
    E_guess = (ν + 1/2) * ω
    return E_guess + potential_minimum
end

function plot_binding_curve(bond_lengths, binding_curve, fit)
    plt = lineplot(bond_lengths, binding_curve;
        title="Binding curve", xlabel="Bond length / bohr", ylabel="Energy / Hartree",
        name="Actual values", canvas=DotCanvas, border=:ascii
    )
    lineplot!(plt, bond_lengths, fit.(bond_lengths); name="Fitted curve")
    show(plt)
    println()
    @info "The two lines shown above should closely match. \
        This indicates the evaluation of the potential is working correctly."
end
