using LinearAlgebra

export ChebyshevPolynomial
export chebyshev_fit, eval_fit
export mateval, inner, non_hermitian_inner
export polynomial_fit

struct ChebyshevPolynomial{T}
    coef::Vector{T}
    order::Int
end

struct Polynomial{T}
    coef::Vector{T}
    order::Int
end

chebyshev_fit(f::Function, xvals::AbstractArray; order::Int=5) = chebyshev_fit(xvals, [f(x) for x in xvals], order=order)

function chebyshev_fit(f::Function, npoints::Int; order::Int=5)
    k = 0:(npoints-1)
    xvals = collect(cos.(π * (k .+ 0.5) / npoints))
    chebyshev_fit(f, xvals, order=order)
end

function chebyshev_fit(x::AbstractArray, y::AbstractArray; order::Int=5)
    T = zeros(length(x), order+1)
    chebyshev_fit!(T, x, y, order=order)
end

function chebyshev_fit!(T, x::AbstractArray, y::AbstractArray; order::Int=5)

    if order < 1
        throw(ArgumentError("Chebyshev degree (order) has to be greater than 0."))
    end

    # x-values need to be scaled and shifted such that the fitting domain
    # becomes -1:1, a requirement from the Chebyshev procedure
    if maximum(x) > 1 || minimum(x) < -1
        throw(BoundsError("Chebyshev fitting can only be performed within the [-1,+1] domain."))
    end

    # Create a matrix T composed of Chebyshev degree Tn(x) along rows (i.e. each row is a degree [T₀(x), T₁(x), T₂(x)...])
    # with different values of x along columns. For example, if we have three values of x (x₀, x₁, x₂) and a degree 3 
    # Chebyshev polynomial the T arrays would look like
    # +--------+-------+-------+
    # | T₀(x₀) | T₁(x₀)| T₂(x₀)|
    # +--------+-------+-------+
    # | T₀(x₁) | T₁(x₁)| T₂(x₁)|
    # +--------+-------+-------+
    # | T₀(x₂) | T₁(x₂)| T₂(x₂)|
    # +--------+-------+-------+

    # Since T₀(x) = 1, the first column is simply
    T[:,1] .= 1

    # T₁(x) = x, hence
    T[:,2] .= x

    # The remaining terms are populated using the recursive relation
    # Tₙ(x) = 2xTₙ₋₁ - Tₙ

    # Loop through columns (n)
    for n in 3:(order+1)
        for i in eachindex(x)
            T[i,n] = 2*x[i]*T[i,n-1] - T[i,n-2]
        end
    end

    # Solve the matrix equation Tc = y 
    c = T \ y

    return ChebyshevPolynomial(c, order)
end

polynomial_fit(f::Function, xvals::AbstractArray; order::Int=5) = polynomial_fit(xvals, [f(x) for x in xvals], order=order)

polynomial_fit(f::Function, xmin, xmax, npoints::Int; order::Int=5) = polynomial_fit(f, range(start=xmin, stop=xmax, length=npoints), order=order)

function polynomial_fit(x::AbstractArray, y::AbstractArray; order::Int=5)
    P = zeros(length(x), order+1)
    polynomial_fit!(P, x, y, order=order)
end

function polynomial_fit!(P, x::AbstractArray, y::AbstractArray; order::Int=5)

    # Create a matrix P composed of polynomails of degree pn(x) along rows (i.e. each row is a degree [p₀(x), p₁(x), p₂(x)...])
    # with different values of x along columns. For example, if we have three values of x (x₀, x₁, x₂) and a degree 3 
    # polynomial the P arrays would look like
    # +--------+-------+-------+
    # | p₀(x₀) | p₁(x₀)| p₂(x₀)|
    # +--------+-------+-------+
    # | p₀(x₁) | p₁(x₁)| p₂(x₁)|
    # +--------+-------+-------+
    # | p₀(x₂) | p₁(x₂)| p₂(x₂)|
    # +--------+-------+-------+

    # Loop through polynomial orders (n = order+1)
    for n in 1:(order+1)
        # Loop through x values
        for i in eachindex(x)

            # Compute polynomial value pₙ(x) = xⁿ 
            P[i,n] = x[i] ^ (n-1)
        end
    end

    # Solve the matrix equation Tc = y 
    c = P \ y

    return Polynomial(c, order)
end

function eval_fit(x, cb::ChebyshevPolynomial{T}) where T

    Tn = zeros(T, cb.order+1)

    Tn[1] = 1
    if cb.order == 0
        return cb.coef[1]
    end

    Tn[2] = x

    for n in 3:(cb.order+1)
        Tn[n] = 2x*Tn[n-1] - Tn[n-2]
    end

    return dot(Tn, cb.coef)
end

function eval_fit(x, pl::Polynomial{T}) where T

    out = 0.0
    for o in 0:pl.order
        out += pl.coef[o+1]*x^o 
    end

    return out
end

# Auxiliary function to evalute mattrix functions
function mateval(f::Function, A::Matrix)
    λ, U = eigen(A)

    fvals = diagm(f.(λ))

    return U * fvals * U'
end

# Auxiliary function to evalute mattrix functions using Chebyshev expansion
function mateval(cb::ChebyshevPolynomial, A::Matrix)

    # Zeroth order is just an identity matrix
    T0 = zeros(size(A))
    T0[diagind(T0)] .= 1.0 

    if cb.order == 0
        return cb.coef[1] .* T0
    end

    # First order is just A
    T1 = similar(A)
    T1 .= A

    out = cb.coef[1] .* T0 + cb.coef[2] .* T1

    T2 = similar(A)

    # Forst third-order and beyond use regular recursive relation
    # Tn = 2xTₙ₋₁ - Tₙ₋₂
    for n in 3:(cb.order+1)
        T2 .= 2 .*A*T1 - T0 
        out += cb.coef[n] .* T2

        T0 .= T1
        T1 .= T2
    end

    return out
end

"""
    inner(A, z0, cb)

Compute the inner product ⟨z₀|f(A)|z₀⟩ where f(A) is approximated by a Chebyshev expansion (cb).
The algorithm implemented here is described by Hallman (https://arxiv.org/abs/2101.00325v1 - Algorithm 3.1)
"""
function inner(A, z0, cb::ChebyshevPolynomial)

    # Alias to Chebyshev coefficients (so we can use 0-indexing)
    α(n) = cb.coef[n+1]

    z1 = A*z0
    ζ0 = z0⋅z0
    ζ1 = z0⋅z1
    s = α(0)*ζ0 + α(1)*ζ1 + α(2)*(2 * (z1⋅z1) - ζ0)

    zⱼ₋₂ = z0
    zⱼ₋₁ = z1
    for j = 2:ceil(Int, cb.order/2)
        zⱼ = 2 * (A*zⱼ₋₁) - zⱼ₋₂
        s = s + α(2j-1) * (2 * (zⱼ₋₁⋅zⱼ) - ζ1) 
        if 2j-1 == cb.order
            break
        end
        s = s + α(2j) * (2 * (zⱼ⋅zⱼ) - ζ0) 

        zⱼ₋₂ = zⱼ₋₁
        zⱼ₋₁ = zⱼ
    end

    return s
end

# No Hermiticity assumed
function non_hermitian_inner(A, z0, pl::Polynomial)

    # Alias to Polynomial coefficients (so we can use 0-indexing)
    α(n) = pl.coef[n+1]

    s = α(0)*(z0⋅z0)

    zn = deepcopy(z0)
    for i = 1:pl.order
        zn = A * zn
        s += α(i) * (z0 ⋅ zn) 
    end

    return s
end

# Hermiticity assumed
function inner(A, z0, pl::Polynomial)
    # Alias to Polynomial coefficients (so we can use 0-indexing)
    α(n) = pl.coef[n+1]

    zo = deepcopy(z0)
    zn = A * zo

    s = α(0)*(z0⋅z0)

    if pl.order == 0
        return s
    end

    s += α(1)*(zo ⋅ zn)
    # Edge case, if the order is just 1
    if pl.order == 1
        return s
    end

    s += α(2)*(zn ⋅ zn)
    # Edge case, if the order is just 1
    if pl.order == 2
        return s
    end

    # Loop through n values up to ⌊order/2
    for n = 2:floor(Int, pl.order/2)

        # Update zn such that zn = Aⁿ⋅z, where n is the loop variable
        # The zo variable represents zₙ₋₁
        zo = zn
        zn = A * zo
        s += α(2*n-1) * (zo ⋅ zn)
        s += α(2*n) * (zn ⋅ zn) 
    end

    # When the order is odd, the loop above missed the final term n = order
    # We add that manually here.
    if isodd(pl.order)
        zo .= zn
        zn .= A * zo
        s += α(pl.order) * (zo ⋅ zn)
    end

    return s
end