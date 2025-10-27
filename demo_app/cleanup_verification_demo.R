# Cleanup Verification Demonstration
# Shows how to verify that modules are truly cleaned up with no leaks

library(shiny)
library(pryr)  # For memory profiling: install.packages("pryr")

cat("\n")
cat("==================================================================\n")
cat("CLEANUP VERIFICATION DEMONSTRATION\n")
cat("==================================================================\n\n")

# ============================================================================
# DIAGNOSTIC UTILITIES
# ============================================================================

#' Check if reactive environment has pending flushes
check_pending_flushes <- function(verbose = TRUE) {
  tryCatch({
    env <- shiny:::.getReactiveEnvironment()
    has_pending <- env$hasPendingFlush()

    if (verbose) {
      if (has_pending) {
        cat("⚠️  Pending flushes exist!\n")
      } else {
        cat("✓ No pending flushes\n")
      }
    }

    return(has_pending)
  }, error = function(e) {
    if (verbose) cat("? Could not check pending flushes\n")
    return(NA)
  })
}

#' Check session busy count
check_session_busy <- function(session, verbose = TRUE) {
  tryCatch({
    busy <- session$.__enclos_env__$private$busyCount

    if (verbose) {
      if (busy > 0) {
        cat("⚠️  Session busy (count:", busy, ")\n")
      } else {
        cat("✓ Session idle (busyCount = 0)\n")
      }
    }

    return(busy)
  }, error = function(e) {
    if (verbose) cat("? Could not check busy count\n")
    return(NA)
  })
}

#' Comprehensive cleanup diagnostics
diagnose_cleanup <- function(module_ref = NULL, session = NULL, label = "") {
  if (nchar(label) > 0) {
    cat("\n=== DIAGNOSTICS:", label, "===\n")
  }

  results <- list()

  # Check observer state
  if (!is.null(module_ref) && !is.null(module_ref$.observer)) {
    destroyed <- tryCatch(
      module_ref$.observer$.destroyed,
      error = function(e) NA
    )
    results$observer_destroyed <- destroyed

    if (isTRUE(destroyed)) {
      cat("✓ Observer destroyed\n")
    } else if (isFALSE(destroyed)) {
      cat("⚠️  Observer still active\n")
    }
  }

  # Check execution count
  if (!is.null(module_ref) && !is.null(module_ref$get_execution_count)) {
    count <- module_ref$get_execution_count()
    results$execution_count <- count
    cat("ℹ  Execution count:", count, "\n")
  }

  # Check pending flushes
  results$has_pending_flushes <- check_pending_flushes(verbose = TRUE)

  # Check session busy
  if (!is.null(session)) {
    results$busy_count <- check_session_busy(session, verbose = TRUE)
  }

  # Check memory
  results$memory_used <- pryr::mem_used()
  cat("ℹ  Memory used:", format(results$memory_used), "\n")

  # Summary
  all_good <- TRUE
  if (isFALSE(results$observer_destroyed)) all_good <- FALSE
  if (isTRUE(results$has_pending_flushes)) all_good <- FALSE
  if (!is.null(results$busy_count) && results$busy_count > 0) all_good <- FALSE

  if (all_good && !is.null(module_ref$.observer)) {
    cat("\n🎉 All checks passed!\n")
  } else if (!is.null(module_ref$.observer)) {
    cat("\n⚠️  Some checks failed!\n")
  }

  invisible(results)
}

# ============================================================================
# MODULE WITH VERIFICATION
# ============================================================================

counterUI <- function(id, label = "Counter") {
  ns <- NS(id)

  div(
    class = "well",
    style = "background-color: #f0f8ff; border-left: 4px solid #3498db;",
    h4(label, style = "color: #2c3e50;"),
    fluidRow(
      column(6,
        actionButton(ns("increment"), "+1", width = "100%")
      ),
      column(6,
        actionButton(ns("decrement"), "-1", width = "100%")
      )
    ),
    br(),
    verbatimTextOutput(ns("value")),
    tags$small(
      class = "text-muted",
      "Module ID: ", id
    )
  )
}

counterServer <- function(id, initial_value = 0) {
  moduleServer(id, function(input, output, session) {
    cat(sprintf("\n[MODULE %s] Initializing...\n", id))

    # State
    count <- reactiveVal(initial_value)
    execution_count <- 0

    # Observer
    obs <- observeEvent(input$increment, {
      new_val <- count() + 1
      count(new_val)
      cat(sprintf("[MODULE %s] Incremented to %d\n", id, new_val))
    })

    obs_dec <- observeEvent(input$decrement, {
      new_val <- count() - 1
      count(new_val)
      cat(sprintf("[MODULE %s] Decremented to %d\n", id, new_val))
    })

    # Output
    output$value <- renderText({
      execution_count <<- execution_count + 1
      cat(sprintf("[MODULE %s] Rendering (execution #%d)\n", id, execution_count))

      paste0(
        "Value: ", count(), "\n",
        "Renders: ", execution_count
      )
    })

    # Cleanup
    cleanup <- function() {
      cat(sprintf("\n[MODULE %s] ========== CLEANUP ==========\n", id))

      cat(sprintf("[MODULE %s] Observer destroyed before:", obs$.destroyed, "\n", id))
      obs$destroy()
      cat(sprintf("[MODULE %s] Observer destroyed after:", obs$.destroyed, "\n", id))

      obs_dec$destroy()

      output$value <- NULL

      cat(sprintf("[MODULE %s] ========== CLEANUP DONE ==========\n\n", id))
    }

    # Verification helper
    verify <- function() {
      list(
        observer_destroyed = obs$.destroyed,
        execution_count = execution_count
      )
    }

    cat(sprintf("[MODULE %s] Initialized!\n", id))

    # Return API with internal observer for verification
    list(
      value = count,
      cleanup = cleanup,
      verify = verify,
      get_execution_count = function() execution_count,
      .observer = obs  # Expose for testing (prefix with . to show it's internal)
    )
  })
}

# ============================================================================
# APP
# ============================================================================

ui <- fluidPage(
  titlePanel("Cleanup Verification Demo"),

  sidebarLayout(
    sidebarPanel(
      h4("Module Management"),

      actionButton("create", "Create Module", class = "btn-success", width = "100%"),
      br(), br(),

      conditionalPanel(
        condition = "output.has_module",
        actionButton("cleanup", "Clean Up Module", class = "btn-warning", width = "100%"),
        br(), br(),
        actionButton("cleanup_ui_only", "Remove UI Only (Memory Leak!)", class = "btn-danger", width = "100%"),
        br(), br()
      ),

      hr(),

      h4("Diagnostics"),
      actionButton("diagnose", "Run Diagnostics", class = "btn-info", width = "100%"),
      br(), br(),
      actionButton("gc_manual", "Force Garbage Collection", width = "100%"),

      hr(),

      h4("Memory"),
      verbatimTextOutput("memory_info")
    ),

    mainPanel(
      div(id = "module-container"),

      conditionalPanel(
        condition = "!output.has_module",
        div(
          class = "alert alert-info",
          h4("No Module Active"),
          p("Click 'Create Module' to start")
        )
      ),

      hr(),

      wellPanel(
        h4("Verification Results"),
        verbatimTextOutput("verification_results")
      ),

      wellPanel(
        h4("How to Use This Demo"),
        tags$ol(
          tags$li(strong("Create a module"), " - Click 'Create Module'"),
          tags$li(strong("Interact"), " - Click increment/decrement buttons"),
          tags$li(strong("Run diagnostics"), " - Click 'Run Diagnostics' to see current state"),
          tags$li(strong("Clean up properly"), " - Click 'Clean Up Module'"),
          tags$li(strong("Verify"), " - Run diagnostics again to verify cleanup"),
          tags$li(strong("Try the leak"), " - Create a module, then click 'Remove UI Only' and run diagnostics")
        ),
        tags$hr(),
        div(
          class = "alert alert-warning",
          strong("Watch the R console!"), " All diagnostic output is logged there."
        )
      )
    )
  )
)

server <- function(input, output, session) {
  # Module reference
  module_ref <- reactiveVal(NULL)

  # Memory tracking
  mem_baseline <- pryr::mem_used()
  mem_history <- reactiveVal(list())

  # Has module flag
  output$has_module <- reactive({
    !is.null(module_ref())
  })
  outputOptions(output, "has_module", suspendWhenHidden = FALSE)

  # Create module
  observeEvent(input$create, {
    if (!is.null(module_ref())) {
      showNotification("Module already exists!", type = "warning")
      return()
    }

    cat("\n")
    cat("==================================================================\n")
    cat("CREATING MODULE\n")
    cat("==================================================================\n")

    mem_before <- pryr::mem_used()

    # Insert UI
    insertUI(
      selector = "#module-container",
      where = "afterBegin",
      ui = div(
        id = "counter-wrapper",
        counterUI("counter1", "Test Counter")
      )
    )

    # Create module
    ref <- counterServer("counter1")
    module_ref(ref)

    mem_after <- pryr::mem_used()

    cat("\nMemory change:", format(mem_after - mem_before), "\n")

    # Update history
    history <- mem_history()
    history$created <- mem_after
    mem_history(history)

    showNotification("Module created!", type = "message")
  })

  # Clean up properly
  observeEvent(input$cleanup, {
    ref <- module_ref()
    if (is.null(ref)) {
      showNotification("No module to clean up!", type = "warning")
      return()
    }

    cat("\n")
    cat("==================================================================\n")
    cat("PROPER CLEANUP\n")
    cat("==================================================================\n")

    # Before diagnostics
    cat("\n--- BEFORE CLEANUP ---\n")
    before <- diagnose_cleanup(ref, session, "BEFORE")

    mem_before <- pryr::mem_used()

    # Cleanup
    ref$cleanup()

    # Wait a bit
    Sys.sleep(0.2)

    # After diagnostics
    cat("\n--- AFTER CLEANUP ---\n")
    after <- diagnose_cleanup(ref, session, "AFTER")

    # Remove UI
    removeUI("#counter-wrapper")

    # Clear reference
    module_ref(NULL)

    # Force GC
    gc()

    mem_after <- pryr::mem_used()

    # Update history
    history <- mem_history()
    history$cleaned <- mem_after
    mem_history(history)

    cat("\nMemory freed:", format(mem_before - mem_after), "\n")

    showNotification("Module cleaned up!", type = "message")
  })

  # Clean up UI only (demonstrates memory leak)
  observeEvent(input$cleanup_ui_only, {
    ref <- module_ref()
    if (is.null(ref)) {
      showNotification("No module to clean up!", type = "warning")
      return()
    }

    cat("\n")
    cat("==================================================================\n")
    cat("BAD CLEANUP (UI ONLY) - MEMORY LEAK!\n")
    cat("==================================================================\n")

    # Before
    cat("\n--- BEFORE (UI ONLY) ---\n")
    diagnose_cleanup(ref, session, "BEFORE UI REMOVAL")

    # Only remove UI - observer still running!
    removeUI("#counter-wrapper")

    # Wait
    Sys.sleep(0.2)

    # After
    cat("\n--- AFTER (UI ONLY) ---\n")
    diagnose_cleanup(ref, session, "AFTER UI REMOVAL")

    cat("\n⚠️⚠️⚠️ MEMORY LEAK! Observer still running! ⚠️⚠️⚠️\n")

    showNotification(
      "UI removed but observer still running - MEMORY LEAK!",
      type = "error",
      duration = 10
    )
  })

  # Run diagnostics
  observeEvent(input$diagnose, {
    cat("\n")
    cat("==================================================================\n")
    cat("RUNNING DIAGNOSTICS\n")
    cat("==================================================================\n")

    ref <- module_ref()
    result <- diagnose_cleanup(ref, session, "CURRENT STATE")

    showNotification("Diagnostics complete - check console!", type = "message")
  })

  # Force GC
  observeEvent(input$gc_manual, {
    cat("\n--- FORCING GARBAGE COLLECTION ---\n")
    mem_before <- pryr::mem_used()
    gc_result <- gc()
    mem_after <- pryr::mem_used()

    print(gc_result)
    cat("Memory freed:", format(mem_before - mem_after), "\n")

    showNotification("Garbage collection complete", type = "message")
  })

  # Memory info
  output$memory_info <- renderText({
    # Reactive to input changes to update display
    input$create
    input$cleanup
    input$cleanup_ui_only
    input$gc_manual

    current_mem <- pryr::mem_used()
    history <- mem_history()

    info <- paste0(
      "Baseline: ", format(mem_baseline), "\n",
      "Current: ", format(current_mem), "\n",
      "Increase: ", format(current_mem - mem_baseline), "\n"
    )

    if (!is.null(history$created)) {
      info <- paste0(
        info,
        "\nAfter create: ", format(history$created), "\n",
        "Create cost: ", format(history$created - mem_baseline)
      )
    }

    if (!is.null(history$cleaned)) {
      info <- paste0(
        info,
        "\nAfter cleanup: ", format(history$cleaned), "\n",
        "Cleanup freed: ", format(history$created - history$cleaned)
      )
    }

    info
  })

  # Verification results
  output$verification_results <- renderText({
    input$diagnose
    input$create
    input$cleanup
    input$cleanup_ui_only

    ref <- module_ref()

    if (is.null(ref)) {
      "No module active.\nCreate a module to run diagnostics."
    } else {
      verification <- ref$verify()

      paste0(
        "Module State:\n",
        "  Observer destroyed: ", verification$observer_destroyed, "\n",
        "  Execution count: ", verification$execution_count, "\n",
        "\nSession State:\n",
        "  Pending flushes: ", check_pending_flushes(verbose = FALSE), "\n",
        "  Busy count: ", check_session_busy(session, verbose = FALSE), "\n",
        "\nInteract with the module, then check diagnostics again."
      )
    }
  })
}

cat("\nTo run this demo:\n")
cat("  shinyApp(ui, server)\n\n")

cat("REQUIREMENTS:\n")
cat("  install.packages('pryr')  # For memory profiling\n\n")

cat("TRY THIS SEQUENCE:\n")
cat("  1. Create module\n")
cat("  2. Run diagnostics - see observer active, no pending flushes\n")
cat("  3. Click increment several times\n")
cat("  4. Run diagnostics - see execution count increase\n")
cat("  5. Clean up properly\n")
cat("  6. Run diagnostics - see observer destroyed!\n")
cat("  7. Create another module\n")
cat("  8. Remove UI only (don't cleanup)\n")
cat("  9. Run diagnostics - observer still active - MEMORY LEAK!\n\n")

cat("==================================================================\n\n")

# Uncomment to run:
# shinyApp(ui, server)
