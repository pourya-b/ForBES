function out = zerofpr_new(prob, opt, lsopt)

% initialize operations counter

ops = Ops_Init();

% initialize gamma and sigma

gam = (1-opt.beta)/prob.Lf;
sig = (1-gam*prob.Lf)/(4*gam);

% display header

if opt.display >= 2
    fprintf('%6s%11s%11s%11s%11s\n', 'iter', 'gamma', 'optim.', 'object.', 'tau');
end

cacheDir.cntSkip = 0;

flagTerm = 0;

MAXIMUM_Lf = 1e14;

t0 = tic();

cache_x = Cache_Init(prob, prob.x0, gam);

for it = 1:opt.maxit

    % backtracking on gamma

    hasGammaChanged = 0;
    if opt.adaptive
        [isGammaOK, cache_x, cache_xbar, ops1] = Cache_CheckGamma(cache_x, gam, opt.beta);
        ops = Ops_Sum(ops, ops1);
        while ~isGammaOK
            prob.Lf = 2*prob.Lf; gam = gam/2; sig = 2*sig;
            hasGammaChanged = 1;
            [isGammaOK, cache_x, cache_xbar, ops1] = Cache_CheckGamma(cache_x, gam, opt.beta);
            ops = Ops_Sum(ops, ops1);
        end
    else
        [cache_x, ops1] = Cache_ProxGradStep(cache_x, gam);
        ops = Ops_Sum(ops, ops1);
        cache_xbar = Cache_Init(prob, cache_x.z, gam);
    end

    % trace stuff

    if it == 1
        cache_0 = cache_x;
    end

    ts(1, it) = toc(t0);
    residual(1, it) = norm(cache_x.FPR, 'inf')/gam;
    if opt.toRecord
        record(:, it) = opt.record(prob, it, gam, cache_0, cache_x, ops);
    end

    % compute FBE at current point
    % (this should count zero operations)
    % will be used to compute the threshold for the line-search

    [cache_x, ops1] = Cache_FBE(cache_x, gam);
    ops = Ops_Sum(ops, ops1);

    objective(1,it) = cache_x.FBE;

    % check for termination

    if ~hasGammaChanged
        if ~opt.customTerm
            if Cache_StoppingCriterion(cache_x, opt.tol)
                msgTerm = 'reached optimum (up to tolerance)';
                flagTerm = 0;
                break;
            end
        else
            flagStop = opt.term(prob, it, gam, cache_0, cache_x, ops);
            if (opt.adaptive == 0 || it > 1) && flagStop
                msgTerm = 'reached optimum (custom criterion)';
                flagTerm = 0;
                break;
            end
        end
    end
    if prob.Lf >= MAXIMUM_Lf
        msgTerm = ['estimate for Lf became too large: ', num2str(prob.Lf)];
        flagTerm = 1;
        break;
    end

    % compute search direction and slope

    if it == 1 || hasGammaChanged
        sk = [];
        yk = [];
    end

    [dir_QN, ~, cacheDir] = ...
        opt.methodfun(prob, opt, it, hasGammaChanged, sk, yk, cache_x.FPR, cacheDir);
    dir_FB = cache_x.FPR;

    % perform line search

    tau = 1.0; % this *must* be 1.0 for this line-search to work
    [cache_x, ops1] = Cache_LineSearch(cache_x, dir_QN);
    ops = Ops_Sum(ops, ops1);
    [cache_tau, ops1] = Cache_LineFBE(cache_x, tau, 1);
    ops = Ops_Sum(ops, ops1);
    if cache_tau.FBE > cache_x.FBE
        [cache_x, ops1] = Cache_LineSearch(cache_x, [], dir_FB);
        ops = Ops_Sum(ops, ops1);
    end
    while cache_tau.FBE > cache_x.FBE
        tau = tau/2;
        [cache_tau, ops1] = Cache_SegmentFBE(cache_x, tau);
        ops = Ops_Sum(ops, ops1);
        cache_DEBUG = Cache_Init(prob, cache_x.z + tau*(dir_FB + dir_QN), gam);
        cache_DEBUG = Cache_FBE(cache_DEBUG, gam);
    end

    % store pair (s, y) to compute next direction

    sk = cache_tau.x - cache_x.x;
    yk = cache_tau.FPR - cache_x.FPR;

    % update iterate

    cache_x = Cache_Init(prob, cache_tau.z, gam);

    % display stuff

    if opt.display == 1
        Util_PrintProgress(it);
    elseif opt.display >= 2
        fprintf('%6d %7.4e %7.4e %7.4e %7.4e\n', it, gam, residual(1,it), objective(1,it), tau);
    end

end

if it == opt.maxit
    msgTerm = 'exceeded maximum iterations';
    flagTerm = 1;
end

if opt.display == 1
    Util_PrintProgress(it, flagTerm);
end

% pack up results

out.name = opt.name;
out.message = msgTerm;
out.flag = flagTerm;
out.x = cache_x.z;
out.iterations = it;
out.operations = ops;
out.residual = residual(1, 1:it);
out.objective = objective(1, 1:it);
out.ts = ts(1, 1:it);
if opt.toRecord, out.record = record; end
out.gam = gam;

end
