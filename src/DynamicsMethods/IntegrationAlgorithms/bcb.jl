
mutable struct BCBCache{uType,rateType,uEltypeNoUnits} <: OrdinaryDiffEq.OrdinaryDiffEqMutableCache
    u::uType
    uprev::uType
    tmp::uType
    k::rateType
    fsalfirst::rateType
    halfdt::uEltypeNoUnits
    cayley::Vector{Matrix{uEltypeNoUnits}}
end

function OrdinaryDiffEq.alg_cache(::BCB,u,rate_prototype,::Type{uEltypeNoUnits},::Type{uBottomEltypeNoUnits},::Type{tTypeNoUnits},uprev,uprev2,f,t,dt,reltol,p,calck,::Val{true}) where {uEltypeNoUnits,uBottomEltypeNoUnits,tTypeNoUnits}
    tmp = zero(rate_prototype)
    k = zero(rate_prototype)
    fsalfirst = zero(rate_prototype)
    halfdt = dt / 2
    cayley = RingPolymers.cayley_propagator(p.beads, dt; half=false)
    BCBCache(u, uprev, k, tmp, fsalfirst, halfdt, cayley)
end

function OrdinaryDiffEq.verify_f2(f, res, p, q, pa, t, integrator, ::BCBCache)
    f(res, p, q, pa, t)
    res == p ? res : OrdinaryDiffEq.throwex(integrator)
end

function OrdinaryDiffEq.initialize!(integrator, cache::BCBCache)
    integrator.fsalfirst = cache.fsalfirst
    integrator.fsallast = cache.k
  
    integrator.kshortsize = 2
    resize!(integrator.k, integrator.kshortsize)
    integrator.k[1] = integrator.fsalfirst
    integrator.k[2] = integrator.fsallast
  
    duprev,uprev = integrator.uprev.x
    integrator.f.f1(integrator.k[2].x[1],duprev,uprev,integrator.p,integrator.t)
    OrdinaryDiffEq.verify_f2(integrator.f.f2, integrator.k[2].x[2], duprev, uprev, integrator.p, integrator.t, integrator, cache)
    integrator.destats.nf += 1
    integrator.destats.nf2 += 1
end

@muladd function OrdinaryDiffEq.perform_step!(integrator, cache::BCBCache, repeat_step=false)
    @unpack t, dt, p = integrator
    (;cayley, halfdt) = cache

    vprev, rprev, acceleration = OrdinaryDiffEq.load_symp_state(integrator)
    v, r, vtmp = OrdinaryDiffEq.alloc_symp_state(integrator)

    copy!(r, rprev)

    step_B!(vtmp, vprev, halfdt, acceleration)

    RingPolymerArrays.transform_to_normal_modes!(vtmp, p.beads.transformation)
    RingPolymerArrays.transform_to_normal_modes!(r, p.beads.transformation)

    step_C!(vtmp, r, cayley)

    RingPolymerArrays.transform_from_normal_modes!(vtmp, p.beads.transformation)
    RingPolymerArrays.transform_from_normal_modes!(r, p.beads.transformation)

    integrator.f.f1(acceleration, vtmp, r, p, t)
    integrator.destats.nf += 1

    step_B!(v, vtmp, halfdt, acceleration)

    OrdinaryDiffEq.store_symp_state!(integrator, cache, acceleration, v)
end
