using LinearAlgebra: Symmetric, SymTridiagonal, inv, I
using RecursiveArrayTools

export RingPolymerParameters
export transform_to_normal_modes!
export transform_from_normal_modes!

struct RingPolymerParameters{T<:AbstractFloat}
    n_beads::UInt
    ω_n::T
    springs::Symmetric{T}
    normal_mode_springs::Vector{T}
    U::Matrix{T}
    quantum_atoms::Vector{UInt}
    tmp::Vector{T}
    function RingPolymerParameters{T}(
        n_beads::Integer, temperature::Real,
        quantum_atoms::Vector{<:Integer}) where {T<:AbstractFloat}

        ω_n = n_beads * temperature
        new(n_beads, ω_n,
            get_spring_matrix(n_beads, ω_n),
            get_normal_mode_springs(n_beads, ω_n), 
            get_normal_mode_transformation(n_beads),
            quantum_atoms,
            zeros(T, n_beads))
    end
end

"""Constructor for choosing specific elements to be quantum."""
function RingPolymerParameters{T}(n_beads::Integer, temperature::Real, atom_types::AbstractVector{Symbol}, quantum_nuclei::Vector{Symbol}) where {T}
    quantum_atoms = findall(in(quantum_nuclei), atom_types)
    RingPolymerParameters{T}(n_beads, temperature, quantum_atoms)
end

"""Constructor for the case where all nuclei are quantum."""
function RingPolymerParameters{T}(n_beads::Integer, temperature::Real, n_atoms::Integer) where {T}
    RingPolymerParameters{T}(n_beads, temperature, collect(1:n_atoms))
end

"""
    get_L(n_beads, mass, ω_n)

Return the Circulant symmetric matrix for the ring polymer springs.
"""
function get_spring_matrix(n_beads::Integer, ω_n::Real)::Symmetric
    if n_beads == 1
        spring = zeros(1, 1)
    elseif n_beads == 2
        spring = [2 -2; -2 2]
    else
        spring = SymTridiagonal(fill(2, n_beads), fill(-1, n_beads-1))
        spring = convert(Matrix, spring)
        spring[end,1] = spring[1, end] = -1
    end
    Symmetric(spring .*  ω_n^2 / 2)
end

get_normal_mode_springs(n_beads::Integer, ω_n::Real) = get_matsubara_frequencies(n_beads, ω_n) .^2 / 2
get_matsubara_frequencies(n::Integer, ω_n::Real) = 2ω_n*sin.((0:n-1)*π/n)

# """
#     get_normal_mode_transformation(n::Int)::Matrix
    
# Get the transformation matrix that converts to normal mode coordinates.
# """
# function get_normal_mode_transformation(n::Int)::Matrix
#     a = ([exp(2π*im/n * j * k) for j=0:n-1, k=0:n-1])
#     (real(a) + imag(a)) / sqrt(n)
# end

"""
Creates normal mode transformation for `n` beads.
"""
function get_normal_mode_transformation(n::Integer)::Matrix
    # Real and imaginary parts of the discrete Fourier transform matrix. 
    U = sqrt(2/n) .* hcat([cos(2π * j * k / n) for j=0:n-1, k=0:n÷2],
                        [sin(2π * j * k / n) for j=0:n-1, k=n÷2+1:n-1])

    # Normalisation
    U[:, 1] ./= sqrt(2)
    iseven(n) && (U[:, n÷2+1] ./= sqrt(2))

    U
end

function transform_to_normal_modes!(p::RingPolymerParameters, R::AbstractArray{T,3}) where {T}
    @views for i in p.quantum_atoms
        for j in axes(R, 1)
            mul!(p.tmp, p.U', R[j,i,:])
            R[j,i,:] .= p.tmp
        end
    end
end

function transform_from_normal_modes!(p::RingPolymerParameters, R::AbstractArray{T,3}) where {T}
    @views for i in p.quantum_atoms
        for j in axes(R, 1)
            mul!(p.tmp, p.U, R[j,i,:])
            R[j,i,:] .= p.tmp
        end
    end
end

function transform!(p::RingPolymerParameters, A::RingPolymerArray)
    if A.normal
        transform_from_normal_modes!(p, A)
    else
        transform_to_normal_modes!(p, A)
    end
    A.normal = !A.normal
end

Base.length(beads::RingPolymerParameters) = beads.n_beads
Base.range(beads::RingPolymerParameters) = range(1; length=length(beads))

"""
    cayley_propagator(beads::RingPolymerParameters{T}, dt::Real; half::Bool=true) where {T}

J. Chem. Phys. 151, 124103 (2019); doi: 10.1063/1.5120282
"""
function cayley_propagator(beads::RingPolymerParameters{T}, dt::Real; half::Bool=true) where {T}

    cay(dtA::Matrix)::Matrix = inv(I - dtA/2) * (I + dtA/2)

    ω_k = get_matsubara_frequencies(length(beads), beads.ω_n)
    prop = [Array{T}(undef, 2, 2) for i=1:length(beads)]
    for (i, ω) in enumerate(ω_k)
        A = [0 1; -ω^2 0]
        prop[i] .= half ? real.(sqrt(cay(dt.*A))) : cay(dt.*A)
    end
    prop
end
