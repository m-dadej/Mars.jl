
function generate_mars(μ::Vector{Float64},
                       σ::Vector{Float64},
                       P::Matrix{Float64},
                       T::Int64;
                       β::Vector{Float64} = Vector{Float64}([]),
                       β_ns::Vector{Float64} = Vector{Float64}([])
                       )

    @assert size(P)[2] == length(μ) == length(σ) "Number of states not equal among provided parameters."

    if size(P)[2] != size(P)[1]
        P = vcat(P, ones(1, size(P)[2]))
        P = P ./ sum(P, dims=1)
    end
    
    k = length(μ)
    n_β = Int(size(β)[1]/k)
    n_β_ns = size(β_ns)[1]
    s_t = [1]
    
    for _ in 1:(T-1)
        push!(s_t, sample(1:k, Weights(P[:, s_t[end]])))
    end
    
    y_s = zeros(T, k)
    X = [ones(T) rand(Normal(0,1), T, n_β + n_β_ns)]
    
    params = [zeros(1 + n_β + n_β_ns) for _ in 1:k]
    [params[i][1] = μ[i] for i in 1:k]     # populate intercepts
    [params[i][2:(n_β+1)] .= β[1+n_β*(i-1):n_β*i] for i in 1:k] # populate switching betas
    [params[i][(n_β+2):(n_β+1+n_β_ns)] .= β_ns for i in 1:k] # populate switching betas
    
    for t in 1:T
        for s in 1:k
            y_s[t, s] = rand(Normal((X*params[s])[t], σ[s])) 
        end       
    end
    
    y = zeros(T)
    for s in 1:k
        y[s_t .== s] .= y_s[s_t .== s, s]
    end

    return y, s_t, X
end

function add_lags(y::Vector{Float64}, p::Int64)

    @assert p >= 0 "p must be non-negative"

    T = size(y)[1]
    x = zeros(T-p, p+1)

    for i in 1:p+1
        x[:,i] .= y[p+2-i:T-i+1]
    end

    return x
end
##

# the parameters structure is as follows:

# 1:k                          - σ
# k+1:(k+k*n_β)                - state switching β aprameters
# (k+k*n_β+1):(k+k*n_β+n_β_ns) - non state switchign β parameters
# (k+k*n_β+n_β_ns+1):end        - transition probabilities


function vec2param_switch(θ::Vector{Float64}, k::Int64, n_β::Int64, n_β_ns::Int64)
    
    σ = θ[1:k]
    # make Vector{Vector{Float64}} of β each containing n_β + n_β_ns elements
    β = [zeros(n_β + n_β_ns + 1) for _ in 1:k]
    
    # fill the first n_β elements with state-switching parameters + intercept (either also if ns)
    [β[i][1] = θ[k+1:(k+k)][i] for i in 1:k]
    [β[i+1][2:n_β+1] .= θ[k+k+1:(k*2 + n_β*k)][1+(n_β)*i:(n_β)*(i+1)] for i in 0:k-1]
    
    # fill the rest of the vectors with non-switching parameters (same for each state)
    if n_β_ns > 0
        [β[i][end-n_β_ns+1:end] .= θ[(k*2 + n_β*k)+1:(k*2 + n_β*k) + n_β_ns] for i in 1:k]
    end

    @views P = reshape(θ[end-(k*(k-1) - 1):end], k-1, k)

    return σ, β, P
end

function vec2param_nonswitch(θ::Vector{Float64}, k::Int64, n_β::Int64, n_β_ns::Int64)
    
    σ = θ[1:k]
    # make Vector{Vector{Float64}} of β each containing n_β + n_β_ns elements
    β = [zeros(n_β + n_β_ns + 1) for _ in 1:k]
    
    [β[i][1] = θ[k+1:(k+1+k*n_β)][1] for i in 1:k]
    [β[i+1][2:n_β+1] .= θ[k+2:(k+1+k*n_β)][1+(n_β)*i:(n_β)*(i+1)] for i in 0:k-1]
    
    # fill the rest of the vectors with non-switching parameters (same for each state)
    if n_β_ns > 0
        [β[i][end-n_β_ns+1:end] .= θ[(k+1+n_β*k+1):(k+1+n_β*k+n_β_ns)] for i in 1:k]
    end

    @views P = reshape(θ[end-(k*(k-1) - 1):end], k-1, k)

    return σ, β, P
end

# the same function as above, but without [β[i][1] = θ[k+1:(k+1+k*n_β)][1] for i in 1:k] and indexes moved
function vec2param_nointercept(θ::Vector{Float64}, k::Int64, n_β::Int64, n_β_ns::Int64)
    
    σ = θ[1:k]
    # make Vector{Vector{Float64}} of β each containing n_β + n_β_ns elements
    β = [zeros(n_β + n_β_ns + 1) for _ in 1:k]
    
    [β[i+1][2:n_β+1] .= θ[k+1:(k+k*n_β)][1+(n_β)*i:(n_β)*(i+1)] for i in 0:k-1]
    
    # fill the rest of the vectors with non-switching parameters (same for each state)
    if n_β_ns > 0
        [β[i][end-n_β_ns+1:end] .= θ[(k+n_β*k+1):(k+n_β*k+n_β_ns)] for i in 1:k]
    end

    @views P = reshape(θ[end-(k*(k-1) - 1):end], k-1, k)

    return σ, β, P
end

function trans_θ(θ::Vector{Float64}, k::Int64, n_β::Int64, n_β_ns::Int64, intercept::String)
    
    # I know, it should be done in a single function. But it's faster apparently.
    if intercept == "switching"
        σ, β, P = vec2param_switch(θ, k, n_β, n_β_ns)
    elseif intercept == "non-switching"
        σ, β, P = vec2param_nonswitch(θ, k, n_β, n_β_ns)
    elseif intercept == "no"
        σ, β, P = vec2param_nointercept(θ, k, n_β, n_β_ns)
    end
    
    
    σ = σ.^2
    P = [P; ones(1, k)]
    P = P ./ sum(P, dims=1)

    return σ, β, P
end


# function below combines vec2param_nonswitch and vec2param_switch
# apparently, it's slower than the two separate functions. Even though it's more concise.

# function vec2param(θ::Vector{Float64}, k::Int64, n_β::Int64, n_β_ns::Int64, intercept::String)
    
#     σ = θ[1:k]
#     # make Vector{Vector{Float64}} of β each containing n_β + n_β_ns elements
#     β = [zeros(n_β + n_β_ns + 1) for _ in 1:k]
    
#     if intercept == "non-switching"
#         last_β = (k+k*n_β + 1)
#         [β[i][1] = θ[k+1:(k+k*n_β + 1)][1] for i in 1:k]
#         [β[i+1][2:n_β+1] .= θ[k+1:last_β][(2 + n_β*i):(1 + n_β*(i+1))] for i in 0:k-1]
#     else
#         last_β = (k*2 + n_β*k)
#         # fill the first n_β elements with state-switching parameters + intercept (either also if ns)
#         [β[i+1][1:n_β+1] .= θ[k+1:last_β][1+(n_β+1)*i:(n_β+1)*(i+1)] for i in 0:k-1]
#     end
    
#     # fill the rest of the vectors with non-switching parameters (same for each state)
#     [β[i][end-n_β_ns+1:end] .= θ[last_β+1:last_β + n_β_ns] for i in 1:k]

#     @views P = reshape(θ[end-(k*(k-1) - 1):end], k-1, k)

#     return σ, β, P
# end




