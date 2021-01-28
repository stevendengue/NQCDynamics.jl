using Unitful
using UnitfulAtomic

export ang_to_au
export au_to_ang

export eV_to_au
export au_to_eV

export eV_per_ang_to_au
export au_to_eV_per_ang

export u_to_au
export au_to_u

export ps_inv_to_au
export au_to_ps_inv

auconvertstrip(u::Unitful.Units, x::Number) = ustrip(auconvert(u, x))

ang_to_au(x) = austrip(x*u"Å")
au_to_ang(x) = auconvertstrip(u"Å", x)

eV_to_au(x) = austrip(x*u"eV")
au_to_eV(x) = auconvertstrip(u"eV", x)

eV_per_ang_to_au(x) = austrip(x*u"eV/Å")
au_to_eV_per_ang(x) = auconvertstrip(u"eV/Å", x)

u_to_au(x) = austrip(x*u"u")
au_to_u(x) = auconvertstrip(u"u", x)

ps_inv_to_au(x) = austrip(x*u"1/ps")
au_to_ps_inv(x) = auconvertstrip(u"1/ps", x)