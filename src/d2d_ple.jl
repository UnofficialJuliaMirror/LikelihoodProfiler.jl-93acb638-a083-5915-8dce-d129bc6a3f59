using NLopt

function params_intervals_d2d(init_params::Vector{Float64},
                             id::Int64,
                             maxf::Float64,
                             loss_f::Function,
                             logscale::Vector{Bool} = fill(false, length(init_params));
                             fit_alg::Symbol=:LN_NELDERMEAD,
                             local_alg::Symbol=:LN_BOBYQA,
                             init_bounds::Vector{Float64} = [1e-9,1e9],
                             tol_val::Float64 = 1e-3,
                             solver::Symbol=:NLOPT)

        # Checks
        (loss_f(init_params) > maxf) && throw(ArgumentError("Check init_params and maxf: loss_func(init_params)should be <= maxf"))
        (init_params[id]<=minimum(init_bounds) || init_params[id]>=maximum(init_bounds)) && throw(ArgumentError("init values are outside of the bounds $init_bounds"))

        global count = 0

        function loss_func(params::Vector{Float64})
                loss = loss_f(params)
                global count
                count::Int64 += 1
                println("f_$count($params), loss=$loss")
                return loss
        end

        # Output
        intervals = Vector{Float64}(2)
        ret_codes = Vector{Symbol}(2)
        count_evals = Vector{Int64}(2)
        loss_final = Vector{Float64}(2)

        # Logscale
        params = copy(init_params)
        n_params = length(params)
        @. params = logscale_check_log(init_params, logscale)
        bounds = logscale_check_bounds(init_bounds, logscale[id])

        function profile_func(id::Int64, params::Vector{Float64})

                if length(params) == 1
                        loss = loss_func(params)
                        return params, loss
                else
                        function fit_params_func(p,g)
                                loss = loss_func(insert!(copy(p),id,params[id]))
                                loss
                         end
                        opt = Opt(fit_alg, length(params)-1)
                        min_objective!(opt, fit_params_func)
                        ftol_abs!(opt,tol_val)
                        (loss,minx,ret) = optimize(opt,deleteat!(copy(params),id))
                        return insert!(minx,id,params[id]), loss
                end
        end

        # init d2d settings
        q = tol_val
        init_loss = loss_func(params)
        delta_alpha = maxf - init_loss
        q_delta_alpha = q*delta_alpha
        dps = zeros(length(params))
        minstepsize = 1e-6 # minumum size of a step
        maxstepsize = 0.4*params[id]
        init_step = maxstepsize/2.1
        maxsteps = 1e3 # not implemented

        for step in (-init_step, init_step)
                # Iterations count
                global count = 0

                step < 0. ? p_id = 1 : p_id = 2
                ps = copy(params)
                dps[id] = step
                loss = init_loss
                while true
                        step = getStepDirect(id, ps, step, q_delta_alpha, loss_func, loss, bounds, minstepsize, maxstepsize)
                        if isnan(step)
                                ret_codes[p_id] = :BOUNDS_REACHED
                                break
                        end
                        dps[id] = step
                        p_trial = ps + dps
                        ps, loss = profile_func(id,p_trial)
                        if loss > init_loss + delta_alpha #*1.2
                                ret_codes[p_id] = :FTOL_REACHED
                                break
                        end
                end
                intervals[p_id] = ps[id]
                count_evals[p_id] = count
                loss_final[p_id] = loss
        end
        println("PLE intervals = $intervals")
        return intervals, count_evals, ret_codes, loss_final
end

function getStepDirect(id::Int64,                   # p[jk] id
                       ps::Vector{Float64},      # current p values
                       last_step::Float64,             # current dp
                       q_delta_alpha::Float64,
                       loss_func::Function,
                       loss::Float64,               # f threshold
                       bounds,
                       minstepsize::Float64,
                       maxstepsize::Float64)

    # bounds
    lb, ub = bounds

    # steps
#    minstepsize = 1e-6 # minumum size of a step
#    maxstepsize = 0.2*ps[id] # maximum size of a step
    stepfaktor = 2

    step = last_step

    if (ps[id]+step <= lb + minstepsize || ps[id]+step >= ub - minstepsize) # jk hit boundaries
            step = step / stepfaktor
            if abs(step) < minstepsize
                    if (step>0)
                        lbub = "upper"
                    else
                        lbub = "lower"
                    end
            end
            println("PLE_$id parameter hit boundary")
            return NaN
    else
            ps[id] = ps[id] + step
            loss_trial = loss_func(ps)
            if (loss_trial - loss) > q_delta_alpha
                    step = step / stepfaktor
                    if abs(step) < minstepsize
                            println("WARNING: could not control step size")
                            step = step * stepfaktor
                    end
            else
                    if ((loss_trial - loss) < q_delta_alpha) && ((loss_trial - loss) >= 0.)
                            step = step * stepfaktor
                            if abs(step) > maxstepsize
                                    step = maxstepsize*sign(step)
                            end
                    end
            end
            println("step=$step")
    return step
    end
end



logscale_check_log(x::Float64, logscale::Bool) = logscale ? log10(x) : x

logscale_check_exp(x::Float64, logscale::Bool) = logscale ? exp10(x) : x

logscale_check_bounds(b::Vector{Float64}, logscale::Bool) = logscale ? Tuple(log10.(b)) : Tuple(b)