#' @import graphics
#' @import multcomp
#' @import stats
#' @import utils
#' @importFrom car residualPlot
#' @importFrom car residualPlots

extrCall <- function (x) 
{
    if (isS4(x)) x@call else x$call
}

extrData <- function (x) 
{
    if (inherits(x, "SuperLearner")) {
        data <- cbind(eval(x$call$X), eval(x$call$Y))
        dimnames(data)[[2]][ncol(data)] <- as.character(x$call$Y[[3]])
    }
    else {
        data <- extrCall(x)$data
        data <- eval(data, envir = globalenv())
    }
    if (!is.data.frame(data)) data <- as.data.frame(as.list(data))
    return(data)
}

mgsub <- function (pattern, replacement, x, ...) 
{
    for (i in 1:length(pattern)) x <- gsub(pattern[i], replacement[i], 
        x, ...)
    return(x)
}

indmatch <- function (x, y) 
{
    tmp <- which(sapply(seq.int(length(y) - length(x) + 1), function(i) identical(x, y[i + (seq_along(x)-1)])))
    return(seq.int(x) - 1 + tmp)
}

adaptx <- function(expData, neModelFit, obs = NULL, xFit = NULL) 
{
    fit1 <- neModelFit
    fit2 <- if (missing(xFit)) attr(expData, "model") else xFit
    vartype <- attr(terms(expData), "vartype")
    
    if (inherits(expData, "weightData")) X <- ifelse(obs, vartype$Xexp[[1]], vartype$Xexp[[2]])
    else if (inherits(expData, "impData")) X <- ifelse(obs, vartype$Xexp[[2]], vartype$Xexp[[1]])
    
    ind <- c(unlist(vartype[c("Y", "M", "C")]), X)
    if (is.na(ind["Y"])) vartype$Y <- ind["Y"] <- all.vars(stats::formula(fit1))[1]
    
    newdat <- expData[, ind]
    colnames(newdat) <- gsub(X, vartype$X, colnames(newdat))
    newdat <- newdat[, unlist(vartype[c("Y", "X", "M", "C")])]
    
    modmat <- model.matrix(stats::formula(fit2), newdat)
    
    return(list(newdat = newdat, modmat = modmat))
}

neModelEst <- function (formula, family, expData, xFit, ...) 
{
    args <- as.list(match.call())[-1L]
    args$weights <- if (inherits(expData, "weightData")) 
      quote(attr(expData, "weights"))
    else if (inherits(expData, "impData")) 
      quote(rep(1, nrow(expData)))
    if (!is.null(args$xFit)) {
        xFit <- eval(args$xFit)
        xFormula <- stats::formula(xFit)
        class(xFormula) <- "Xformula"
        vartypeCheck <- attr(neTerms(xFormula), "vartype")
        vartype <- attr(attr(expData, "terms"), "vartype")
        if (!identical(vartype[names(vartypeCheck)], vartypeCheck)) 
            stop("Exposure or covariates of propensity score model and mediator model don't match!")
        wrapFUN <- if (inherits(xFit, "vglm"))
          function(x) model.frame(stats::formula(xFit)[-2], x)
        else 
          function(x) return(x)
        family <- if (inherits(xFit, "vglm")) 
            xFit@family@vfamily[1]
        else xFit$family$family
        family <- c("gaussian", "binomial", "poisson", "multinomial")[mapply(function(x,
            y) grepl(y, x), as.character(family), c("gaussian", "binomial",
            "poisson", "multinomial"))]
        dispersion <- if (inherits(xFit, "vglm")) 
            xFit@misc$dispersion
        else summary(xFit)$dispersion 
        predictFUN <- if (inherits(xFit, "vglm")) 
          VGAM::predictvglm
        else if (inherits(xFit, "vgam")) 
          VGAM::predict.vgam
        else predict
        dfun <- switch(family, 
                       gaussian = function(x) dnorm(x, mean = predictFUN(xFit, newdata = wrapFUN(expData), type = "response"), sd = sqrt(dispersion)), 
                       binomial = function(x) {if (is.factor(x)) x <- as.numeric(x) - 1
                                               return(dbinom(x, size = 1, prob = predictFUN(xFit, newdata = wrapFUN(expData), type = "response")))}, 
                       poisson = function(x) dpois(x, lambda = predictFUN(xFit, newdata = wrapFUN(expData), type = "response")),
                       multinomial = function(x) {pred <- predictFUN(xFit, newdata = wrapFUN(expData), type = "response")
                                                  return(sapply(1:nrow(expData), function(i) pred[i, as.character(x[i])]))})
        denominator <- if (inherits(expData, "weightData")) 
          dfun(expData[, vartype$Xexp[1]])
        else if (inherits(expData, "impData")) 
          dfun(expData[, vartype$Xexp[2]])
        args$weights <- eval(args$weights) / denominator
    }
    args$data <- quote(expData)
    args$expData <- args$xFit <- NULL
    fit <- suppressWarnings(do.call("glm", args))
    mc <- match.call()
    fit$call <- attr(fit, "call") <- mc
    attr(fit, "terms") <- fit$terms
    attr(attr(fit, "terms"), "vartype") <- attr(attr(expData, "terms"), "vartype")
    return(fit)
}
