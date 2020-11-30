module Dynamics

    using ..Electronics
    using ..Systems
    
    """
        DynamicsParameters
        
    Parameters for use with the DifferentialEquations.jl solvers.

    Acts as a simple container to allow two unrelated quantities to be passed to the solver.
    """
    struct DynamicsParameters
        system::Systems.SystemParameters
        electronics::Electronics.ElectronicContainer
    end

    function differential!(du::DynamicalVariables, u::DynamicalVariables, p::DynamicsParameters, t)
        get_positions(du) .= get_momenta(u) ./ p.system.masses
        get_momenta(du) .= get_force(p, u)
    end
    
    function get_force(p::DynamicsParameters, u::DynamicalVariables)
        Electronics.calculate_derivative!(p.electronics, get_positions(u))
        -p.electronics.D0
    end

end # module