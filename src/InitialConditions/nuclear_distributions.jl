
export DynamicalDistribution

using Random: AbstractRNG, rand!
using Distributions
using UnitfulAtomic

struct DynamicalVariate <: VariateForm end

struct DynamicalDistribution{V,R,S,N} <: Sampleable{DynamicalVariate,Continuous}
    velocity::V
    position::R
    size::NTuple{S,Int}
    state::N
    type::Symbol
end
DynamicalDistribution(velocity, position, size; state=0, type=:adiabatic) =
    DynamicalDistribution(velocity, position, size, state, type)

Base.eltype(s::DynamicalDistribution{<:Sampleable,R}) where {R} = eltype(s.velocity)
Base.eltype(s::DynamicalDistribution{<:AbstractArray,R} where {R}) = eltype(austrip.(s.velocity[1]))
Base.size(s::DynamicalDistribution) = s.size

function Distributions.rand(rng::AbstractRNG, s::Sampleable{DynamicalVariate})
    Distributions._rand!(rng, s, [Array{eltype(s)}(undef, size(s)) for i=1:2])
end

function Distributions._rand!(rng::AbstractRNG, s::DynamicalDistribution, x::Vector{<:Array})
    i = rand(rng, 1:length(s.position))
    x[1] .= select_item(s.velocity, i, s.size)
    x[2] .= select_item(s.position, i, s.size)
    x
end

pick(s::DynamicalDistribution, i::Integer) = [select_item(s.velocity, i, s.size), select_item(s.position, i, s.size)]

# Indexed selections
select_item(x::Vector{<:AbstractArray}, i::Integer, ::NTuple) = austrip.(x[i])
select_item(x::Vector{<:Number}, i::Integer, size::NTuple) = fill(austrip.(x[i]), size)

# Sampled selection
select_item(x::Sampleable{Univariate}, ::Integer, size::NTuple) = austrip.(rand(x, size))

# Deterministic selections
select_item(x::Real, ::Integer, size::NTuple) = austrip.(fill(x, size))
select_item(x::Matrix, ::Integer, ::NTuple) = austrip.(x)
select_item(x::AbstractArray{T,3}, ::Integer, ::NTuple) where T = austrip.(x)

function Base.show(io::IO, s::DynamicalDistribution) 
    print(io, "DynamicalDistribution with size: ", size(s))
end

function Base.show(io::IO, ::MIME"text/plain", s::DynamicalDistribution)
    print(io, "DynamicalDistribution:\n  ",
          "size: ", size(s), "\n  ",
          "state: ", s.state, "\n  ",
          "type: ", s.type)
end

struct BoltzmannVelocityDistribution{T} <: Sampleable{Multivariate,Continuous}
    dist::MvNormal{T}
end

function BoltzmannVelocityDistribution(temperature, masses)
    dist = MvNormal(sqrt.(temperature ./ masses))
    BoltzmannVelocityDistribution(dist)
end

Base.length(s::BoltzmannVelocityDistribution) = length(s.dist)
function Distributions._rand!(rng::AbstractRNG, s::BoltzmannVelocityDistribution, x::AbstractVector{<:Real})
    Distributions._rand!(rng, s.dist, x)
end
function select_item(x::BoltzmannVelocityDistribution, ::Integer, size::Tuple{Int,Int})
    permutedims(rand(x, size[1]))
end
function select_item(x::BoltzmannVelocityDistribution, ::Integer, size::Tuple{Int,Int,Int})
    out = zeros(eltype(x), size)
    for i=1:size[3]
        out[:,:,i] .= permutedims(rand(x, size[1]))
    end
    return out
end
