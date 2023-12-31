#' Writes an enrichment dataset file for use in Cytoscape EnrichmentMap.
#'
#' @param results (list) list with ouput results from \link[fedup]{runFedup}
#' @param resultsFolder (char) name of folder to store result file(s)
#' @return Table of pathway enrichment and depletion results formatted as a
#' 'Generic results file'. Rows represent tested pathways. Columns represent:
#' \itemize{
#'     \item pathway -- pathway ID (must match pathway IDs in the GMT file
#'         provided to \link[fedup]{plotFemap};
#'     \item description -- pathway name or description;
#'     \item pvalue -- enrichment pvalue;
#'     \item qvalue -- BH-corrected pvalue;
#'     \item status -- +1 or -1, to identify enriched or depleted pathways
#'         (+1 maps to red, -1 maps to blue)
#' }
#' @examples
#' # Load example data
#' data(geneDouble)
#' data(pathwaysGMT)
#' # Run fedup
#' fedupRes <- runFedup(geneDouble, pathwaysGMT)
#' # Write out results to temp folder
#' resultsFolder <- tempdir()
#' writeFemap(fedupRes, resultsFolder)
#' @importFrom data.table fwrite
#' @importFrom dplyr select mutate %>%
#' @export
writeFemap <- function(results, resultsFolder) {
    resultsEM <- lapply(seq_along(results), function(i) {
        x <- results[[i]] %>%
            select("pathway", "pvalue", "qvalue", "status") %>%
            mutate("description" = gsub("\\%.*", "", results[[i]]$pathway)) %>%
            mutate("status" =
                ifelse(results[[i]]$status == "enriched", "1", "-1")) %>%
            select("pathway", "description", "pvalue", "qvalue", "status")
        fname <- file.path(
            resultsFolder,
            paste0("femap_", names(results)[[i]], ".txt")
        )
        fwrite(x, fname, sep = "\t", col.names = TRUE, quote = FALSE)
        message("Wrote out EM-formatted fedup results file to ", fname)
    })
}

#' Draws a network representation of overlaps among pathway enrichment
#' results using EnrichmentMap (EM) in Cytoscape.
#'
#' @param gmtFile (char) absolute path to GMT file (generated via
#' \link[fedup]{writePathways})
#' @param resultsFolder (char) absolute path to folder with fedup results
#' (generated via \link[fedup]{writeFemap})
#' @param pvalue (numeric) pvalue cutoff (value between 0 and 1; default 1)
#' @param qvalue (numeric) qvalue cutoff (value between 0 and 1; default 1)
#' @param formSim (character) formula to calculate similarity score
#' (one of OVERLAP, JACCARD, COMBINED; default COMBINED)
#' @param edgeSim (numeric) edge similarity score cutoff
#' (value between 0 and 1; default 0.375)
#' @param combSim (numeric) when coefficients=COMBINED this parameter is used
#' to determine what percentage to use for JACCARD and OVERLAP when combining
#' their value (value between 0 to 1; default 0.5)
#' @param chartData (char) node chart data (one of NES_VALUE, P_VALUE,
#' FDR_VALUE, PHENOTYPES, DATA_SET, EXPRESSION_SET, or NONE;
#' default NES_VALUE)
#' @param clustAlg (character) clusterMaker algorith
#' (one of AFFINITY_PROPAGATION, CLUSTER_FIZZIFIER, GLAY, CONNECTED_COMPONENTS,
#' MCL, SCPS; default MCL)
#' @param clustWords (integer) maximum words to include in autoAnnotate
#' cluster label (default 3)
#' @param hideNodeLabels (logical) if TRUE hides the node label in the EM;
#' cluster labels generated via AutoAnnotate remain visible
#' @param netName (char) name for EM in Cytoscape (default generic)
#' @param netFile (char) name of output image (supports png, pdf, svg,
#' jpeg image formats)
#' @return File name of image to which the network is exported and an open
#' session of Cytoscape (side effect of plotting EM). NULL if Cytoscape
#' is not running locally.
#' @examples
#' # Load example data
#' data(geneDouble)
#' data(pathwaysGMT)
#' # Run fedup
#' fedupRes <- runFedup(geneDouble, pathwaysGMT)
#' # Write out results to temp folder
#' resultsFolder <- tempdir()
#' writeFemap(fedupRes, resultsFolder)
#' # Write out gmt formatted pathawy annotations to temp file
#' gmtFile <- tempfile("pathwaysGMT", fileext = ".gmt")
#' writePathways(pathwaysGMT, gmtFile)
#' # Plot enrichment map
#' netFile <- tempfile("fedup_EM", fileext = ".png")
#' plotFemap(
#'     gmtFile = gmtFile,
#'     resultsFolder = resultsFolder,
#'     qvalue = 0.05,
#'     hideNodeLabels = TRUE,
#'     netName = "fedup_EM",
#'     netFile = netFile
#' )
#' @import RCy3
#' @export
#' @usage
#' plotFemap(
#'     gmtFile,
#'     resultsFolder,
#'     pvalue = 1,
#'     qvalue = 1,
#'     formSim = "COMBINED",
#'     edgeSim = 0.375,
#'     combSim = 0.5,
#'     chartData = "NES_VALUE",
#'     clustAlg = "MCL",
#'     clustWords = 3,
#'     hideNodeLabels = FALSE,
#'     netName = "generic",
#'     netFile = "png"
#' )
plotFemap <- function(gmtFile, resultsFolder, pvalue = 1, qvalue = 1,
    formSim = "COMBINED", edgeSim = 0.375, combSim = 0.5,
    chartData = "NES_VALUE", clustAlg = "MCL", clustWords = 3,
    hideNodeLabels = FALSE, netName = "generic", netFile = "png") {
    emap <- tryCatch({
            cytoscapePing()
            if (netName %in% getNetworkList()) {
                deleteNetwork(netName)
            }
            message(" => building the network")
            em_command <- paste(
                "enrichmentmap mastermap rootFolder=", resultsFolder,
                "networkName=", netName,
                "commonGMTFile=", gmtFile,
                "pvalue=", pvalue,
                "qvalue=", qvalue,
                "coefficients=", formSim,
                "similaritycutoff=", edgeSim,
                "combinedConstant=", combSim
            )
            response <- commandsGET(em_command)
            message(" => setting network chart data")
            ch_command <- paste0("enrichmentmap chart data=", chartData)
            response <- commandsGET(ch_command)
            message(" => annotating the network via AutoAnnotate")
            aa_command <- paste(
                "autoannotate annotate-clusterBoosted",
                "clusterAlgorithm=", clustAlg,
                "maxWords=", clustWords,
                "network=", netName
            )
            response <- commandsGET(aa_command)
            message(" => applying a force-directed network layout")
            ln_command <- paste(
                "layout force-directed",
                "network=", netName
            )
            response <- commandsGET(ln_command)
            if (hideNodeLabels) {
                setNodeFontSizeDefault(0, "EM1_Visual_Style")
            }
            fitContent()
            message(" => drawing out the network to ", netFile)
            exportImage(netFile)
        },
        error = function(x) {
            return(NULL)
        })
    return(emap)
}
